import {Component, OnInit, ChangeDetectionStrategy} from '@angular/core';
import {GamesService} from "../../../services/games.service";
import {Router} from "@angular/router";
import {UserService} from "../../../services/user.service";

@Component({
    selector: 'app-users',
    templateUrl: './users.component.html',
    styleUrl: './users.component.css',
    changeDetection: ChangeDetectionStrategy.Eager,
    standalone: false
})
export class UsersComponent implements OnInit{
  constructor(private _user:UserService,private router:Router) {
  }
  users:any;
  error:any;

  ngOnInit() {
    // this.username=this.act.snapshot.paramMap.get('username');
    this._user.getAllUsers().subscribe(res=>{
      this.users=res;
    },err=>{
      console.log(err);
    })
  }

  deleteUser(id:any){
    this._user.deleteUser(id).subscribe(res=>{
      location.reload();
    },error => {
    })
  }
}
