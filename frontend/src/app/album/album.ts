import { Component } from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { inject } from '@angular/core';
import { PhotoService } from '../photo.service';
import { map } from 'rxjs/operators';
import { combineLatest, switchMap, filter, tap, finalize, catchError, of } from 'rxjs';
import { toSignal } from '@angular/core/rxjs-interop';
import { signal } from '@angular/core';

@Component({
  selector: 'app-album',
  imports: [],
  templateUrl: './album.html',
  styleUrl: './album.scss'
})
export class AlbumComponent {
  readonly route = inject(ActivatedRoute);
  readonly service = inject(PhotoService);

  readonly isLoading = signal(false);

  private readonly shootId$ = this.route.paramMap.pipe(
    map(params => params.get('shoot') || null),
  );

  private readonly albumId$ = this.route.paramMap.pipe(
    map(params => params.get('album') || null),
  );

  private readonly album$ = combineLatest([this.shootId$, this.albumId$]).pipe(
    filter(([shootId, albumId]) => !!shootId && !!albumId),
    tap(() => this.isLoading.set(true)),
    switchMap(([shootId, albumId]) => this.service.getAlbum(shootId!, albumId!)),
    tap(() => this.isLoading.set(false)),
    catchError((err) => {
      console.error('Error loading album:', err);
      this.isLoading.set(false);
      return of(null); // Return null or handle the error as neededc
    })
  );

  readonly album = toSignal(this.album$, { initialValue: null });

}
