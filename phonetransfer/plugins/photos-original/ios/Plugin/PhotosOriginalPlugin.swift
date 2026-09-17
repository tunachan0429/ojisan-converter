// PhotosOriginalPlugin.swift — PhoneTransfer iOS העברות
// Capacitor 8 (CAPBridgedPlugin) 形式。
// 役割: 写真ライブラリの原本取出し(PHAssetResource)＋裏転送(background URLSession)＋保存。
// JSは進捗UIのみ。原本の読出しと送信は全てここで行う。
// 前提: Info.plist に NSPhotoLibraryUsageDescription / NSPhotoLibraryAddUsageDescription。
import Foundation
import Photos
import PhotosUI
import Security
import CommonCrypto
import Capacitor

@objc(PhotosOriginalPlugin)
public class PhotosOriginalPlugin: CAPPlugin, CAPBridgedPlugin, URLSessionDelegate, URLSessionTaskDelegate, PHPickerViewControllerDelegate {
    public let identifier = "PhotosOriginalPlugin"
    public let jsName = "PhotosOriginal"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "pickAssets", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getOriginals", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "uploadChunk", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "apiRequest", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "downloadFile", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveBytes", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveToPhotos", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "shareFile", returnType: CAPPluginReturnPromise),
    ]

    // WebViewのfetchは自己署名を拒否するため、JSON系APIは全てピンニング済みセッション経由。
    private lazy var fgSession: URLSession = {
        let conf = URLSessionConfiguration.ephemeral
        conf.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: conf, delegate: self, delegateQueue: nil)
    }()

    private lazy var bgSession: URLSession = {
        let conf = URLSessionConfiguration.background(withIdentifier: "com.phonetransfer.lan.upload")
        conf.isDiscretionary = false
        conf.sessionSendsLaunchEvents = true
        conf.httpMaximumConnectionsPerHost = 3
        return URLSession(configuration: conf, delegate: self, delegateQueue: nil)
    }()
    private var pickerCallId: String?
    private var pinnedFpByTask: [Int: String] = [:]
    private let fpLock = NSLock()

    // MARK: - 権限
    private func ensureAuth(_ done: @escaping () -> Void) {
        let st = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if st == .authorized || st == .limited { done(); return }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in done() }
    }

    // MARK: - pickAssets({limit, videos}) -> { assets: [{id, filename, creationDate, isLive, width, height}] }
    // iOS標準ピッカー(PHPicker)。原本選択はOS任せのため権限は最小でよい。
    @objc func pickAssets(_ call: CAPPluginCall) {
        ensureAuth {
            DispatchQueue.main.async {
                var conf = PHPickerConfiguration(photoLibrary: .shared())
                conf.selectionLimit = call.getInt("limit") ?? 100
                if call.getBool("videos", false) {
                    conf.filter = .any(of: [.images, .livePhotos, .videos])
                } else {
                    conf.filter = .any(of: [.images, .livePhotos])
                }
                conf.preferredAssetRepresentationMode = .current
                let picker = PHPickerViewController(configuration: conf)
                picker.delegate = self
                self.bridge?.saveCall(call)
                self.pickerCallId = call.callbackId
                self.bridge?.viewController?.present(picker, animated: true)
            }
        }
    }

    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let id = pickerCallId, let call = bridge?.getSavedCall(id) else { return }
        pickerCallId = nil
        let ids = results.compactMap { $0.assetIdentifier }
        if ids.isEmpty {
            call.resolve(["assets": []])
            bridge?.releaseCall(call)
            return
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var out: [[String: Any]] = []
        assets.enumerateObjects { asset, _, _ in
            let resources = PHAssetResource.assetResources(for: asset)
            let hasPhoto = resources.contains { $0.type == .photo || $0.type == .fullSizePhoto }
            let hasVideo = resources.contains { $0.type == .pairedVideo || $0.type == .fullSizePairedVideo || $0.type == .video }
            let isLive = asset.mediaSubtypes.contains(.photoLive) || (hasPhoto && hasVideo && asset.mediaType == .image)
            out.append([
                "id": asset.localIdentifier,
                "filename": asset.value(forKey: "filename") as? String ?? resources.first?.originalFilename ?? "IMG",
                "creationDate": asset.creationDate?.timeIntervalSince1970 ?? 0,
                "isLive": isLive,
                "width": asset.pixelWidth, "height": asset.pixelHeight,
            ])
        }
        call.resolve(["assets": out])
        bridge?.releaseCall(call)
    }

    // MARK: - getOriginals({ids}) -> { files: [{id, filename, path, size, mtime, liveGroupId, liveRole}] }
    // HEIC/MOVのまま tmp/PhotoTransfer/ に実体化。変換しない。
    @objc func getOriginals(_ call: CAPPluginCall) {
        guard let ids = call.getArray("ids", String.self), !ids.isEmpty else {
            call.reject("ids-required"); return
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        if assets.count == 0 { call.reject("no-assets"); return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoTransfer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var out: [[String: Any]] = []
        let group = DispatchGroup()
        let lock = NSLock()
        var firstError: String?
        assets.enumerateObjects { asset, _, _ in
            let resources = PHAssetResource.assetResources(for: asset)
            let liveGroup = asset.mediaSubtypes.contains(.photoLive) ? asset.localIdentifier : ""
            for res in resources {
                let t = res.type
                let isOriginal = (t == .photo || t == .fullSizePhoto || t == .video || t == .fullSizeVideo || t == .pairedVideo || t == .fullSizePairedVideo)
                if !isOriginal { continue }
                group.enter()
                let dest = dir.appendingPathComponent(res.originalFilename)
                if FileManager.default.fileExists(atPath: dest.path) {
                    let sz = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
                    lock.lock()
                    out.append(["id": asset.localIdentifier, "filename": res.originalFilename, "path": dest.path, "size": sz,
                                "mtime": asset.creationDate?.timeIntervalSince1970 ?? 0,
                                "liveGroupId": liveGroup,
                                "liveRole": (t == .pairedVideo || t == .fullSizePairedVideo) ? "video" : "photo"])
                    lock.unlock()
                    group.leave()
                    continue
                }
                let opt = PHAssetResourceRequestOptions()
                opt.isNetworkAccessAllowed = true
                PHAssetResourceManager.default().writeData(for: res, toFile: dest, options: opt) { err in
                    lock.lock(); defer { lock.unlock(); group.leave() }
                    if let err = err { if firstError == nil { firstError = err.localizedDescription }; return }
                    let sz = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
                    out.append(["id": asset.localIdentifier, "filename": res.originalFilename, "path": dest.path, "size": sz,
                                "mtime": asset.creationDate?.timeIntervalSince1970 ?? 0,
                                "liveGroupId": liveGroup,
                                "liveRole": (t == .pairedVideo || t == .fullSizePairedVideo) ? "video" : "photo"])
                }
            }
        }
        group.notify(queue: .main) {
            if out.isEmpty {
                call.reject(firstError ?? "export-failed"); return
            }
            call.resolve(["files": out])
        }
    }

    // MARK: - uploadChunk({filePath, url, offset, length, jwt, fileToken, pinnedFp})
    // 同一ファイル内は逐次呼ぶこと(並列PATCH禁止)。background sessionはファイルからのみ送信可のためchunkを一時ファイル化。
    // 自前の証明書ピンニング必須(自己署名のため)。pinnedFp=サーバー証明書DERのSHA256 hex。
    @objc func uploadChunk(_ call: CAPPluginCall) {
        guard let filePath = call.getString("filePath"),
              let urlStr = call.getString("url"),
              let jwt = call.getString("jwt"),
              let fileToken = call.getString("fileToken"),
              let url = URL(string: urlStr) else {
            call.reject("bad-args"); return
        }
        let offset = call.getInt("offset") ?? 0
        let length = call.getInt("length") ?? (8 * 1024 * 1024)
        let pinnedFp = (call.getString("pinnedFp") ?? "").lowercased()
        do {
            let fh = try FileHandle(forReadingFrom: URL(fileURLWithPath: filePath))
            defer { try? fh.close() }
            try fh.seek(toOffset: UInt64(offset))
            let data = fh.readData(ofLength: length)
            let chunkURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".chunk")
            try data.write(to: chunkURL)
            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
            req.setValue(fileToken, forHTTPHeaderField: "X-File-Token")
            req.setValue(String(offset), forHTTPHeaderField: "Upload-Offset")
            req.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
            let task = bgSession.uploadTask(with: req, fromFile: chunkURL)
            fpLock.lock(); pinnedFpByTask[task.taskIdentifier] = pinnedFp; fpLock.unlock()
            bridge?.saveCall(call)
            task.taskDescription = [call.callbackId, chunkURL.path].joined(separator: "|")
            task.resume()
        } catch {
            call.reject("chunk-failed: \(error.localizedDescription)")
        }
    }

    // MARK: TLSピンニング (URLSessionDelegate)
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil); return
        }
        let taskId = (challenge as? URLSessionTaskChallenge)?.taskIdentifier
        var pinned = ""
        if let id = taskId { fpLock.lock(); pinned = pinnedFpByTask[id] ?? ""; fpLock.unlock() }
        var fp = ""
        if let cert = SecTrustGetCertificateAtIndex(trust, 0) {
            let data = SecCertificateCopyData(cert) as Data
            var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest) }
            fp = digest.map { String(format: "%02x", $0) }.joined()
        }
        if !pinned.isEmpty && fp == pinned {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else if pinned.isEmpty {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        fpLock.lock(); pinnedFpByTask.removeValue(forKey: task.taskIdentifier); fpLock.unlock()
        guard let desc = task.taskDescription else { return }
        let parts = desc.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let cb = bridge?.getSavedCall(parts[0])
        try? FileManager.default.removeItem(atPath: parts[1])
        guard let cb = cb else { return }
        if let error = error as NSError?, error.code == NSURLErrorCancelled, error.domain == NSURLErrorDomain {
            // ピンニング不一致の可能性
            cb.reject("pin-mismatch")
            bridge?.releaseCall(cb)
            return
        }
        if let error = error {
            cb.reject("upload-failed: \(error.localizedDescription)")
            bridge?.releaseCall(cb)
            return
        }
        let code = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        let off = (task.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Upload-Offset") ?? "0"
        cb.resolve(["uploadOffset": Int(off) ?? 0, "status": code])
        bridge?.releaseCall(cb)
    }

    // MARK: - apiRequest({method, url, headers, bodyText, pinnedFp}) — JSON系API汎用
    @objc func apiRequest(_ call: CAPPluginCall) {
        guard let urlStr = call.getString("url"), let url = URL(string: urlStr) else {
            call.reject("bad-url"); return
        }
        let pinnedFp = (call.getString("pinnedFp") ?? "").lowercased()
        var req = URLRequest(url: url)
        req.httpMethod = call.getString("method") ?? "GET"
        if let headers = call.getObject("headers") {
            for k in headers.keys {
                if let v = headers[k] as? String { req.setValue(v, forHTTPHeaderField: k) }
            }
        }
        if let body = call.getString("bodyText") {
            req.httpBody = body.data(using: .utf8)
            if req.value(forHTTPHeaderField: "Content-Type") == nil {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        bridge?.saveCall(call)
        let task = fgSession.dataTask(with: req) { data, resp, err in
            guard let saved = self.bridge?.getSavedCall(call.callbackId) else { return }
            if let err = err {
                saved.reject("request-failed: \(err.localizedDescription)")
                self.bridge?.releaseCall(saved)
                return
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            var h: [String: String] = [:]
            if let rh = (resp as? HTTPURLResponse)?.allHeaderFields {
                for (k, v) in rh { h["\(k)".lowercased()] = "\(v)" }
            }
            saved.resolve([
                "status": code,
                "headers": h,
                "body": data.flatMap { String(data: $0, encoding: .utf8) } ?? "",
            ])
            self.bridge?.releaseCall(saved)
        }
        fpLock.lock(); pinnedFpByTask[task.taskIdentifier] = pinnedFp; fpLock.unlock()
        task.resume()
    }

    // MARK: - downloadFile({url, jwt, filename, pinnedFp}) — 受信の実体取得(URLSessionDownloadTask)
    @objc func downloadFile(_ call: CAPPluginCall) {
        guard let urlStr = call.getString("url"), let url = URL(string: urlStr),
              let filename = call.getString("filename") else {
            call.reject("bad-args"); return
        }
        let pinnedFp = (call.getString("pinnedFp") ?? "").lowercased()
        var req = URLRequest(url: url)
        if let jwt = call.getString("jwt") {
            req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        }
        bridge?.saveCall(call)
        let task = fgSession.downloadTask(with: req) { tmp, resp, err in
            guard let saved = self.bridge?.getSavedCall(call.callbackId) else { return }
            defer { self.bridge?.releaseCall(saved) }
            if let err = err {
                saved.reject("download-failed: \(err.localizedDescription)"); return
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (code == 200 || code == 206), let tmp = tmp else {
                saved.reject("download-status: \(code)"); return
            }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoTransfer", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(UUID().uuidString + "_" + filename)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: tmp, to: dest)
                let sz = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
                saved.resolve(["path": dest.path, "size": sz, "status": code])
            } catch {
                saved.reject("move-failed: \(error.localizedDescription)")
            }
        }
        fpLock.lock(); pinnedFpByTask[task.taskIdentifier] = pinnedFp; fpLock.unlock()
        task.resume()
    }

    // MARK: - saveBytes({filename, base64}) -> {path} — 受信データの一時保存
    @objc func saveBytes(_ call: CAPPluginCall) {
        guard let name = call.getString("filename"), let b64 = call.getString("base64"),
              let data = Data(base64Encoded: b64) else {
            call.reject("bad-args"); return
        }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTransfer", isDirectory: true)
            .appendingPathComponent(UUID().uuidString + "_" + name)
        do {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: dest)
            call.resolve(["path": dest.path, "size": data.count])
        } catch {
            call.reject("write-failed: \(error.localizedDescription)")
        }
    }

    // MARK: - saveToPhotos({path}) — Windows→iPhoneの写真・動画保存
    @objc func saveToPhotos(_ call: CAPPluginCall) {
        guard let p = call.getString("path") else { call.reject("bad-args"); return }
        let url = URL(fileURLWithPath: p)
        let ext = url.pathExtension.lowercased()
        let isVideo = ["mov", "mp4", "m4v"].contains(ext)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in
            PHPhotoLibrary.shared().performChanges({
                if isVideo {
                    PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
                } else {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
                }
            }) { ok, err in
                if ok { call.resolve(["saved": true]) }
                else { call.reject(err?.localizedDescription ?? "save-failed") }
            }
        }
    }

    // MARK: - shareFile({path}) — zip等の共有シート表示
    @objc func shareFile(_ call: CAPPluginCall) {
        guard let p = call.getString("path") else { call.reject("bad-args"); return }
        DispatchQueue.main.async {
            let vc = UIActivityViewController(activityItems: [URL(fileURLWithPath: p)], applicationActivities: nil)
            vc.completionWithItemsHandler = { completed, _, _, _ in
                call.resolve(["completed": completed])
            }
            if let pop = vc.popoverPresentationController {
                pop.sourceView = self.bridge?.viewController?.view
                pop.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
                pop.permittedArrowDirections = []
            }
            self.bridge?.viewController?.present(vc, animated: true)
        }
    }
}
