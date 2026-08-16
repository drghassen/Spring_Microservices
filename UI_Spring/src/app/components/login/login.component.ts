import { Component, OnInit, ChangeDetectionStrategy } from '@angular/core';
import { AuthService } from '../../services/auth.service';
import { Router } from '@angular/router';

@Component({
    selector: 'app-login',
    templateUrl: './login.component.html',
    styleUrl: './login.component.css',
    changeDetection: ChangeDetectionStrategy.Eager,
    standalone: false
})
export class LoginComponent implements OnInit{
  user={
    username:'',
    password:''
  }
  err:undefined;
  token:any
  constructor(private _auth:AuthService,private router:Router){}
  ngOnInit(): void {

  }
  login(){
    this._auth.login(this.user)
    .subscribe(res=>{
      this.token=res;
      localStorage.setItem('token',this.token.message)
      this.router.navigate(['/home']);
    },
    err=>{
      this.err=err
    }
    )
    this.ngOnInit();
  }
}
