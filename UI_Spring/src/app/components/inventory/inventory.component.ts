import {Component, OnInit, ChangeDetectionStrategy} from '@angular/core';
import {AuthService} from "../../services/auth.service";
import {LibraryService} from "../../services/library.service";
import {ActivatedRoute} from "@angular/router";

@Component({
    selector: 'app-inventory',
    templateUrl: './inventory.component.html',
    styleUrl: './inventory.component.css',
    changeDetection: ChangeDetectionStrategy.Eager,
    standalone: false
})
export class InventoryComponent implements OnInit{
  username:any;
  library:any;

  //injection
  constructor(private _library:LibraryService,private _auth:AuthService,private act:ActivatedRoute) {
  }

  //get library
  ngOnInit(): void {
    this.username=this.act.snapshot.paramMap.get('username');

    //get username from token
    //this.username=this._auth.getUserDataFromToken();

    //listner to backend
    this._library.getAllGames(this.username).subscribe(res=>{
      this.library=res;
      //console.log(this.library)
    })
  }

}
