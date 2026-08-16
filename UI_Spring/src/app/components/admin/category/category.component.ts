import {Component, OnInit, ChangeDetectionStrategy} from '@angular/core';
import {ActivatedRoute, Router} from "@angular/router";
import {GamesService} from "../../../services/games.service";

@Component({
    selector: 'app-category',
    templateUrl: './category.component.html',
    styleUrl: './category.component.css',
    changeDetection: ChangeDetectionStrategy.Eager,
    standalone: false
})
export class CategoryComponent implements OnInit
{
  id:any;
  categories:any;

  constructor(private _games:GamesService,private router:Router) {
  }
    ngOnInit() {
      this._games.getCategory().subscribe(res=>{
        this.categories=res;
        console.log(res)
      },err=>{
        console.log(err);
      })
    }

  deleteCategory(id:any){
    this._games.deleteCat(id).subscribe(res=>{
      console.log(res)
      location.reload();
    },error => {
      console.log(error)
    })
  }



}
