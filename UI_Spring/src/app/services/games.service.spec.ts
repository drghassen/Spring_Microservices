import { TestBed } from '@angular/core/testing';
import { GamesService } from './games.service';
import { httpTestProviders } from '../testing';

describe('GamesService', () => {
  let service: GamesService;

  beforeEach(() => {
    TestBed.configureTestingModule({ providers: httpTestProviders });
    service = TestBed.inject(GamesService);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
