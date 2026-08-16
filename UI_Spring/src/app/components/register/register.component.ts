import { Component, OnInit, ChangeDetectionStrategy } from '@angular/core';
import { AuthService } from '../../services/auth.service';
import {Router} from "@angular/router";

@Component({
    selector: 'app-register',
    templateUrl: './register.component.html',
    styleUrl: './register.component.css',
    changeDetection: ChangeDetectionStrategy.Eager,
    standalone: false
})
export class RegisterComponent implements OnInit{
  err=undefined;
  token:any;
  user:any={
    name:'',
    username:'',
    email:'',
    password:'',
    address:''
  }
  constructor(private _auth:AuthService,private router:Router){}

  image:any=undefined;
  select(e:any){
    this.image=e.target.files[0];
  }
  ngOnInit(): void {
  }
  register(){
    let fd=new FormData()
    fd.append('name',this.user.name)
    fd.append('username',this.user.username)
    fd.append('email',this.user.email)
    fd.append('password',this.user.password)
    fd.append('address',this.user.address)
    fd.append('file',this.image)
    this._auth.register(fd)
    .subscribe(
      res=>{
        this.token=res;
        localStorage.setItem('token',this.token.message)
        this.router.navigate(['/home']);
      }
            ,err=> {
        this.err=err;
      }
    )
  }
}
