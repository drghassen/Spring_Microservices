import { TestBed } from '@angular/core/testing';
import { OrdersService } from './orders.service';
import { httpTestProviders } from '../testing';

describe('OrdersService', () => {
  let service: OrdersService;

  beforeEach(() => {
    TestBed.configureTestingModule({ providers: httpTestProviders });
    service = TestBed.inject(OrdersService);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
