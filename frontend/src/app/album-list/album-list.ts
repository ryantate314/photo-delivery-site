import { Component, inject, signal } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { toSignal } from '@angular/core/rxjs-interop';
import { catchError, filter, finalize, map, of, switchMap, tap } from 'rxjs';
import { PhotoService } from '../photo.service';

@Component({
  selector: 'app-album-list',
  imports: [RouterLink],
  templateUrl: './album-list.html',
  styleUrl: './album-list.scss'
})
export class AlbumListComponent {
  private readonly route = inject(ActivatedRoute);
  private readonly service = inject(PhotoService);

  /** Max photos rendered per album; CSS hides any that don't fit on a single row. */
  readonly previewCount = 8;

  readonly isLoading = signal(false);

  readonly shootId = toSignal(
    this.route.paramMap.pipe(map(params => params.get('shoot'))),
    { initialValue: null }
  );

  private readonly albums$ = this.route.paramMap.pipe(
    map(params => params.get('shoot')),
    filter((shootId): shootId is string => !!shootId),
    tap(() => this.isLoading.set(true)),
    switchMap(shootId => this.service.getAlbums(shootId).pipe(
      catchError(err => {
        console.error('Error loading albums:', err);
        return of(null);
      }),
      finalize(() => this.isLoading.set(false))
    ))
  );

  readonly albums = toSignal(this.albums$, { initialValue: null });
}
