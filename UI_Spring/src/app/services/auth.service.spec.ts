import { TestBed } from '@angular/core/testing';
import { AuthService } from './auth.service';
import { httpTestProviders } from '../testing';

describe('AuthService', () => {
  let service: AuthService;

  beforeEach(() => {
    TestBed.configureTestingModule({ providers: httpTestProviders });
    service = TestBed.inject(AuthService);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
