import { Injectable } from '@angular/core';
import {HttpClient, HttpHeaders, HttpParams} from "@angular/common/http";
import {AuthService} from "./auth.service";
import {Observable} from "rxjs";
import { environment } from '../../environments/environment';

@Injectable({
  providedIn: 'root'
})
export class UserService {

  constructor(private http:HttpClient, private auth:AuthService) {
  }

  private url = environment.apiUrl+'/users/'
  private urlAdmin = environment.apiUrl+'/user/admin'

  //get images!

  getUserImageByUsername(username:any): Observable<Blob>{
    const headers = new HttpHeaders({
      ...this.auth.getAuthorizationHeaders(),
    });
    return this.http.get(`${this.url}${username}/image`,{headers, responseType:'blob'});
  }


  updateById(id:any,user:any){
    const headers = new HttpHeaders({
      ...this.auth.getAuthorizationHeaders(),
    });
    return this.http.put(`${this.url}update/${id}`,user,{headers});
  }
  getAllUsers(){
    const headers = new HttpHeaders({
      ...this.auth.getAuthorizationHeaders(),
    });
    return this.http.get(`${this.urlAdmin}`,{headers});
  }

  getUserById(id:any){
    const headers = new HttpHeaders({
      ...this.auth.getAuthorizationHeaders(),
    });
    return this.http.get(`${this.url}/${id}`,{headers});
  }

  deleteUser(id:any){
    const headers = new HttpHeaders({
      ...this.auth.getAuthorizationHeaders(),
    });
    return this.http.delete(`${this.url}${id}`,{headers});
  }

  updateByUsername( username:any,user:any){
    //headers and params
    const headers = new HttpHeaders({
      ...this.auth.getAuthorizationHeaders(),
    });
    return this.http.put(`${this.url}update/username/${username}`,user,{headers});
  }


  getUserByUsername(username: any) {
   // console.log(username)

    // headers
    const headers = new HttpHeaders({
      ...this.auth.getAuthorizationHeaders(),
    });

    // Make the GET request with the username in the path
    return this.http.get(`${this.url}username/${username}`, { headers });
  }


}
