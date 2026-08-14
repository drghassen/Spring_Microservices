import { ComponentFixture, TestBed } from '@angular/core/testing';
import { CreategameComponent } from './creategame.component';
import { componentTestImports, componentTestProviders } from '../../../../testing';

describe('CreategameComponent', () => {
  let component: CreategameComponent;
  let fixture: ComponentFixture<CreategameComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      declarations: [CreategameComponent],
      imports: componentTestImports,
      providers: componentTestProviders
    })
    .compileComponents();

    fixture = TestBed.createComponent(CreategameComponent);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
