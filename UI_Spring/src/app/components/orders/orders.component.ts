import {Component, OnInit, ChangeDetectionStrategy} from '@angular/core';
import {GamesService} from "../../services/games.service";
import {AuthService} from "../../services/auth.service";
import {OrdersService} from "../../services/orders.service";
import {ActivatedRoute} from "@angular/router";

@Component({
    selector: 'app-orders',
    templateUrl: './orders.component.html',
    styleUrl: './orders.component.css',
    changeDetection: ChangeDetectionStrategy.Eager,
    standalone: false
})
export class OrdersComponent implements OnInit{
  constructor(private act:ActivatedRoute,private _orders:OrdersService) {
  }
  username:any;
  error:any;
  id:any;
  orders:any
  ngOnInit() {
    this.username=this.act.snapshot.paramMap.get('username');
    this._orders.getUserOrders(this.username).subscribe(res=>{
      this.orders=res;
      //console.log(this.orders)
    },err=>{
      console.log(err);
    })
  }
}
