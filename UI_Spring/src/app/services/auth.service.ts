import { HttpClient } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { environment } from '../../environments/environment';

@Injectable({
  providedIn: 'root'
})
export class AuthService {

  constructor(private http:HttpClient) {
   }

   private url = environment.apiUrl+'/auth/'

   register(user:any){
    return this.http.post(this.url+'register',user);
  }




  login(user:any){
    return this.http.post(this.url+'login',user);
  }

  isLoggedIn(){
    const data = this.getUserDataFromToken();
    if(!data){
      return false;
    }
    if(data.exp && Date.now() >= data.exp * 1000){
      this.logout();
      return false;
    }
    return true;
  }

  getUserDataFromToken(){
    const token=localStorage.getItem('token');
    if(!token){
      return null;
    }
    const payload = token.split('.')[1];
    if(!payload){
      this.logout();
      return null;
    }
    try{
      const normalizedPayload = payload
        .replace(/-/g, '+')
        .replace(/_/g, '/');
      const paddedPayload = normalizedPayload.padEnd(
        normalizedPayload.length + (4 - normalizedPayload.length % 4) % 4,
        '='
      );
      return JSON.parse(window.atob(paddedPayload));
    }catch{
      this.logout();
      return null;
    }
  }

  getUsername(){
    return this.getUserDataFromToken()?.sub ?? null;
  }

  isAdmin(){
    return this.getUsername() === 'admin';
  }

  getAuthorizationHeaders(): Record<string, string>{
    const token = localStorage.getItem('token');
    return token ? { Authorization: `Bearer ${token}` } : {};
  }

  logout(){
    localStorage.removeItem('token');
  }

}
