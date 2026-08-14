import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { FormsModule, ReactiveFormsModule } from '@angular/forms';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatMenuModule } from '@angular/material/menu';
import { NoopAnimationsModule } from '@angular/platform-browser/animations';
import { provideRouter, RouterModule } from '@angular/router';
import { of } from 'rxjs';
import { AuthService } from './services/auth.service';
import { GamesService } from './services/games.service';
import { LibraryService } from './services/library.service';
import { OrdersService } from './services/orders.service';
import { UserService } from './services/user.service';

/** Common Angular dependencies used by the shallow component tests. */
export const componentTestImports = [
  FormsModule,
  ReactiveFormsModule,
  RouterModule,
  MatButtonModule,
  MatIconModule,
  MatMenuModule,
  NoopAnimationsModule
];

/**
 * Runs HTTP-backed services against Angular's testing backend and supplies an
 * in-memory router. No component test can issue a real network request.
 */
export const httpTestProviders = [
  provideHttpClient(),
  provideHttpClientTesting(),
  provideRouter([])
];

const authServiceStub = {
  register: () => of({}),
  login: () => of({}),
  isAdmin: () => false,
  isLoggedIn: () => false,
  getUsername: () => null,
  getAuthorizationHeaders: () => ({}),
  logout: () => undefined
};

const gamesServiceStub = {
  addCategory: () => of({}),
  addToCart: () => undefined,
  clearFromCart: () => undefined,
  deleteCat: () => of({}),
  deleteGame: () => of({}),
  findByName: () => of({ content: [], totalElements: 0, totalPages: 0 }),
  getAllGames: () => of([]),
  getCartItems: () => [],
  getCategory: () => of([]),
  getCategoryById: () => of({}),
  getGameById: () => of({ id: 1, name: '', category: {}, avaiblity: 0 }),
  GetGamesImages: () => of(new Blob()),
  modifyGameById: () => of({}),
  postGame: () => of({}),
  removeFromCart: () => undefined,
  updateCat: () => of({})
};

const libraryServiceStub = {
  getAllGames: () => of({ games: [] })
};

const ordersServiceStub = {
  createOrder: () => of({}),
  getUserOrders: () => of([])
};

const userServiceStub = {
  deleteUser: () => of({}),
  getAllUsers: () => of([]),
  getUserById: () => of({}),
  getUserByUsername: () => of({}),
  getUserImageByUsername: () => of(new Blob()),
  updateById: () => of({}),
  updateByUsername: () => of({})
};

/** Test doubles keep component creation tests deterministic and offline. */
export const componentTestProviders = [
  ...httpTestProviders,
  { provide: AuthService, useValue: authServiceStub },
  { provide: GamesService, useValue: gamesServiceStub },
  { provide: LibraryService, useValue: libraryServiceStub },
  { provide: OrdersService, useValue: ordersServiceStub },
  { provide: UserService, useValue: userServiceStub }
];
