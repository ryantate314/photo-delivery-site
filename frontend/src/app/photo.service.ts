import { Injectable } from '@angular/core';
import { Album } from './album.model';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { inject } from '@angular/core';

import { environment } from '../environments/environment';

@Injectable({
  providedIn: 'root'
})
export class PhotoService {
  private readonly http = inject(HttpClient);

  getAlbum(shootId: string, albumId: string): Observable<Album> {
    return this.http.get<Album>(`${environment.apiUrl}/shoots/${shootId}/albums/${albumId}`);
  }

  getAlbums(shootId: string): Observable<Album[]> {
    return this.http.get<Album[]>(`${environment.apiUrl}/shoots/${shootId}/albums`);
  }
}
