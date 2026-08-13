import { Component, OnInit } from '@angular/core';
import { AuthService } from '../../services/auth.service';
import { Router } from '@angular/router';
import {GamesService} from "../../services/games.service";
import {Observable} from "rxjs";

@Component({
  selector: 'app-header',
  templateUrl: './header.component.html',
  styleUrl: './header.component.css',
})
export class HeaderComponent implements OnInit{
  username:string | null = null;
  constructor(public _auth:AuthService,private router:Router){
  }
  ngOnInit(
  ) {
    this.username=this._auth.getUsername();
  }

  logout(){
    this._auth.logout();
    this.username = null;
    this.router.navigate(['/login']);
  }

}
