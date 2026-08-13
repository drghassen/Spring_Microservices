import { Injectable } from '@angular/core';
import {HttpClient, HttpHeaders} from "@angular/common/http";
import { environment } from '../../environments/environment';
import {AuthService} from "./auth.service";

@Injectable({
  providedIn: 'root'
})
export class OrdersService {

  constructor(private http:HttpClient, private _auth:AuthService) { }
  private url=environment.apiUrl+'/orders'

  createOrder(order:any){
    const headers = new HttpHeaders({
      ...this._auth.getAuthorizationHeaders(),
    });

    return this.http.post(`${this.url}`,order,{headers});
  }

  getUserOrders(username:any){
    const headers = new HttpHeaders({
      ...this._auth.getAuthorizationHeaders(),
    });
    return this.http.get(`${this.url}/${username}`,{headers});
  }
}
