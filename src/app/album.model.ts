export interface Album {
  id: string;
  shootId: string;
  photos: Photo[];
  /** Zip file download URL */
  downloadUrl: string;
}

export interface Photo {
  thumbnailUrl: string;
  downloadUrl: string;
}

