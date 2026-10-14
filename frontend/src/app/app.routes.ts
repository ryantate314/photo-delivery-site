import { Routes } from '@angular/router';
import { AlbumComponent } from './album/album';

export const routes: Routes = [
  { path: ':shoot/:album', component: AlbumComponent },
];
