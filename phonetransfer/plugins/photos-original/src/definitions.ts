// TypeScript contract for PhotosOriginal (Capacitor JS side)
export interface PTAsset {
  id: string; filename: string; creationDate: number;
  isLive: boolean; width: number; height: number;
}
export interface PTFile {
  id: string; filename: string; path: string; size: number;
  mtime: number; liveGroupId: string; liveRole: 'photo' | 'video';
}
export interface PhotosOriginalPlugin {
  pickAssets(opts: { limit?: number; videos?: boolean }): Promise<{ assets: PTAsset[] }>;
  getOriginals(opts: { ids: string[] }): Promise<{ files: PTFile[] }>;
  uploadChunk(opts: {
    filePath: string; url: string; offset: number; length?: number;
    jwt: string; fileToken: string; pinnedFp: string;
  }): Promise<{ uploadOffset: number; status: number }>;
  apiRequest(opts: {
    method: string; url: string; headers?: Record<string, string>;
    bodyText?: string; pinnedFp: string;
  }): Promise<{ status: number; headers: Record<string, string>; body: string }>;
  saveBytes(opts: { filename: string; base64: string }): Promise<{ path: string; size: number }>;
  downloadFile(opts: { url: string; jwt?: string; filename: string; pinnedFp: string }): Promise<{ path: string; size: number; status: number }>;
  saveToPhotos(opts: { path: string }): Promise<{ saved: boolean }>;
  shareFile(opts: { path: string }): Promise<{ completed: boolean }>;
}
