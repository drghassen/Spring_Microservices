import {Component, OnInit, ChangeDetectionStrategy} from '@angular/core';
import {AuthService} from "../../../../services/auth.service";
import {ActivatedRoute, Router} from "@angular/router";
import {UserService} from "../../../../services/user.service";

@Component({
    selector: 'app-addmodify',
    templateUrl: './addmodify.component.html',
    styleUrl: './addmodify.component.css',
    changeDetection: ChangeDetectionStrategy.Eager,
    standalone: false
})
export class AddmodifyComponent implements OnInit{
  err=undefined;
  token:any;
  user:any={
    name:'',
    username:'',
    email:'',
    password:'',
    address:''
  }
  id:any;
  success?:any;
  constructor(private _user:UserService,private _auth:AuthService,private router:Router,private act:ActivatedRoute){}

  image:any=undefined;
  select(e:any){
    this.image=e.target.files[0];
  }
  ngOnInit(): void {
    this.id = this.act.snapshot.paramMap.get('userId');
      if (this.id!=undefined){
      this._user.getUserById(this.id).subscribe(
        res=>{
          this.user=res
          this.user.password=''
        },
        err=>{
        }
      )
    }
  }
  updateUser(){
    this._user.updateById(this.id,this.user).subscribe(res=>{
      this.success="User Update avec ID: "+this.id;
    },err=>{

    })
  }
  addUser(){
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
          this.router.navigate(['/users']);
        }
        ,err=> {
          this.err=err;
        }
      )
  }

}
