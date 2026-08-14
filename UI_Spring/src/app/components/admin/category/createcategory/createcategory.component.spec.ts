import { ComponentFixture, TestBed } from '@angular/core/testing';
import { CreatecategoryComponent } from './createcategory.component';
import { componentTestImports, componentTestProviders } from '../../../../testing';

describe('CreatecategoryComponent', () => {
  let component: CreatecategoryComponent;
  let fixture: ComponentFixture<CreatecategoryComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      declarations: [CreatecategoryComponent],
      imports: componentTestImports,
      providers: componentTestProviders
    })
    .compileComponents();

    fixture = TestBed.createComponent(CreatecategoryComponent);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
