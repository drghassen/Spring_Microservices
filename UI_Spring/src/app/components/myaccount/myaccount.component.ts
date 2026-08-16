import { Component, OnInit, ChangeDetectionStrategy } from '@angular/core';
import {AuthService} from "../../services/auth.service";
import {ActivatedRoute, Router} from "@angular/router";
import {UserService} from "../../services/user.service";

@Component({
    selector: 'app-myaccount',
    templateUrl: './myaccount.component.html',
    styleUrl: './myaccount.component.css',
    changeDetection: ChangeDetectionStrategy.Eager,
    standalone: false
})
export class MyaccountComponent implements OnInit {
  user:any={
    name:'',
    address:'',
    email:'',
    password:'',
  }
  image: string | ArrayBuffer | null = '';
  username:any;
  constructor(private _user:UserService, private router:Router,private act:ActivatedRoute){}

  ngOnInit(): void {
    this.username=this.act.snapshot.paramMap.get('username');
   // console.log(this.username)
    this._user.getUserByUsername(this.username).subscribe(res=>{
      this.user=res;
      this.user.password='';
    })

  this.loadImage()
  }

  loadImage(): void {
    this._user.getUserImageByUsername(this.username).subscribe(
      (imageBlob: Blob) => {
        const reader = new FileReader();
        reader.onloadend = () => {
          this.image = reader.result; // Sets the image URL for binding
        };
        reader.readAsDataURL(imageBlob);
      },
      (error) => {
        console.error('Error loading image', error);
      }
    );
  }
  modify(){
    this.username=this.act.snapshot.paramMap.get('username');
    this._user.updateByUsername(this.username,this.user).subscribe(res=>{
      this.router.navigate(['home']);
    })
  }
}
