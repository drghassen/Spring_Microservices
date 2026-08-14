import { Router } from '@angular/router';

import { AuthGuard } from './auth.guard';
import { AuthService } from '../services/auth.service';

describe('AuthGuard', () => {
  let authService: jasmine.SpyObj<AuthService>;
  let router: jasmine.SpyObj<Router>;
  let guard: AuthGuard;

  beforeEach(() => {
    authService = jasmine.createSpyObj<AuthService>('AuthService', ['isLoggedIn']);
    router = jasmine.createSpyObj<Router>('Router', ['navigate']);
    guard = new AuthGuard(authService, router);
  });

  it('allows navigation for an authenticated user', () => {
    authService.isLoggedIn.and.returnValue(true);

    expect(guard.canActivate()).toBeTrue();
    expect(router.navigate).not.toHaveBeenCalled();
  });

  it('redirects an unauthenticated user to login', () => {
    authService.isLoggedIn.and.returnValue(false);

    expect(guard.canActivate()).toBeFalse();
    expect(router.navigate).toHaveBeenCalledWith(['./login']);
  });
});
