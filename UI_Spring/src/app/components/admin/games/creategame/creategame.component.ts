import {Component, OnInit} from '@angular/core';
import {AuthService} from "../../../../services/auth.service";
import {ActivatedRoute, Router} from "@angular/router";
import {GamesService} from "../../../../services/games.service";

@Component({
  selector: 'app-creategame',
  templateUrl: './creategame.component.html',
  styleUrl: './creategame.component.css'
})
export class CreategameComponent implements OnInit{
  err:string | undefined = undefined;
  categories:any;
  token:any;
  success:any;
  error:any;
  game:any={
    name:'',
    description:'',
    avaiblity:'',
    price:'',
    categoryId:''
  }
  id:any
  constructor(private _game:GamesService,private router:Router,  private act: ActivatedRoute){}

  ngOnInit() {
    this.id = this.act.snapshot.paramMap.get('gameId');
    if (this.id == undefined){
      this._game.getCategory().subscribe(
        res=>{
          this.categories=res
          if (!this.game.categoryId && this.categories?.length) {
            this.game.categoryId = this.categories[0].id;
          }
          // console.log(this.categories)
          // console.log(res)
        },
        err=>{
          // console.log(err)
        }
      )
    }else {
      this._game.getCategory().subscribe(
        res=>{
          this.categories=res
          if (!this.game.categoryId && this.categories?.length) {
            this.game.categoryId = this.categories[0].id;
          }
          // console.log(this.categories)
          // console.log(res)
        },
        err=>{
          // console.log(err)
        }
      )
      this._game.getGameById(this.id).subscribe(res=>{
        this.game=res;
        console.log(this.game)
      })
    }
  }

  image:any=undefined;
  select(e:any){
    this.image=e.target.files[0];
  }
  modify(){
    this._game.modifyGameById(this.id,this.game).subscribe(res=>{
      this.success= "Game Updated! "
    },err=>{
      this.error= "Game Not Updated!"
    })
  }
  addGame(){
    if (!this.game.categoryId) {
      this.err = "Please create/select a category before adding a game.";
      return;
    }

    if (!this.image) {
      this.err = "Please select a game image.";
      return;
    }

    let fd=new FormData()
    fd.append('name',this.game.name)
    fd.append('description',this.game.description)
    fd.append('avaiblity',this.game.avaiblity.toString())
    fd.append('price',this.game.price.toString())
    fd.append('categoryId',this.game.categoryId.toString())
    //fd.append('data',JSON.stringify(this.game))
    fd.append('file',this.image)
    console.log(this.game)
    console.log(fd)
    this._game.postGame(fd)
      .subscribe(
        res=>{
          this.router.navigate(['/home']);
        }
        ,err=> {
          this.err=err?.error?.detail || 'Error occured!';
        }
      )
  }
}
