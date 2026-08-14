import { TestBed } from '@angular/core/testing';
import { LibraryService } from './library.service';
import { httpTestProviders } from '../testing';

describe('LibraryService', () => {
  let service: LibraryService;

  beforeEach(() => {
    TestBed.configureTestingModule({ providers: httpTestProviders });
    service = TestBed.inject(LibraryService);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
