import { Routes } from '@angular/router';
import { AlbumComponent } from './album/album';
import { AlbumListComponent } from './album-list/album-list';

export const routes: Routes = [
  // Must precede ':shoot/:album' so "all" isn't treated as an album id.
  { path: ':shoot/all', component: AlbumListComponent },
  { path: ':shoot/:album', component: AlbumComponent },
];
