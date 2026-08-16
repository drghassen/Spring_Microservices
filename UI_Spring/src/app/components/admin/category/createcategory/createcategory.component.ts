import {Component, OnInit, ChangeDetectionStrategy} from '@angular/core';
import {AuthService} from "../../../../services/auth.service";
import {GamesService} from "../../../../services/games.service";
import {ActivatedRoute, Router} from "@angular/router";

@Component({
    selector: 'app-createcategory',
    templateUrl: './createcategory.component.html',
    styleUrl: './createcategory.component.css',
    changeDetection: ChangeDetectionStrategy.Eager,
    standalone: false
})
export class CreatecategoryComponent implements OnInit{
  err=undefined;
  token:any;
  category:any={
    name:'',
    description:''
  }
  success:any;
  error:any;
  id:any
  constructor(private _game:GamesService,private router:Router,private act:ActivatedRoute,){}

  ngOnInit() {
    this.id = this.act.snapshot.paramMap.get('categoryId');
    if (this.id != undefined){
      this._game.getCategoryById(this.id).subscribe(res=>{
        this.category=res;
      })
    }

  }
  modify(){
    this.id = this.act.snapshot.paramMap.get('categoryId');
    this._game.updateCat(this.id,this.category).subscribe(res=>{
      this.success= "Category Updated! "
    },err=>{
      this.error= "Category Not Updated!"
    })
  }

  addCategory(){
    this._game.addCategory(this.category)
      .subscribe(
        res=>{
          this.router.navigate(['/categories']);
        }
        ,err=> {
          this.err=err;
        }
      )
  }

}
