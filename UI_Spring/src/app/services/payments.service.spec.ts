import { TestBed } from '@angular/core/testing';
import { PaymentsService } from './payments.service';
import { httpTestProviders } from '../testing';

describe('PaymentsService', () => {
  let service: PaymentsService;

  beforeEach(() => {
    TestBed.configureTestingModule({ providers: httpTestProviders });
    service = TestBed.inject(PaymentsService);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
