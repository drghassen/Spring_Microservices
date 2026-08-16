import {Component, OnInit, ChangeDetectionStrategy} from '@angular/core';
import {ActivatedRoute, Router} from "@angular/router";
import {OrdersService} from "../../../services/orders.service";
import {GamesService} from "../../../services/games.service";

@Component({
    selector: 'app-games',
    templateUrl: './games.component.html',
    styleUrl: './games.component.css',
    changeDetection: ChangeDetectionStrategy.Eager,
    standalone: false
})
export class GamesComponent implements OnInit{
  constructor(private _games:GamesService,private router:Router) {
  }
  games:any;
  error:any;
  ngOnInit() {
   // this.username=this.act.snapshot.paramMap.get('username');
    this._games.getAllGames().subscribe(res=>{
      this.games=res;
    },err=>{
      console.log(err);
    })
  }
  deleteGame(id:any){
    this._games.deleteGame(id).subscribe(res=>{
      console.log(res)
      location.reload();
    },error => {
      console.log(error)
    })
    this.router.navigate(['/home']);
  }
}
