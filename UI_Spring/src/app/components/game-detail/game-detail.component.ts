import {Component, OnInit, ChangeDetectionStrategy} from '@angular/core';
import {ActivatedRoute} from "@angular/router";
import {AuthService} from "../../services/auth.service";
import {GamesService} from "../../services/games.service";

@Component({
    selector: 'app-game-detail',
    templateUrl: './game-detail.component.html',
    styleUrl: './game-detail.component.css',
    changeDetection: ChangeDetectionStrategy.Eager,
    standalone: false
})
export class GameDetailComponent implements OnInit {
  game: any;
  id: any;
  gameAdded: any;

  image: string | ArrayBuffer | null = '';
  constructor(private _game: GamesService, private act: ActivatedRoute) {
  }

  ngOnInit(): void {
    this.id = this.act.snapshot.paramMap.get('id');
    this._game.getGameById(this.id)
      .subscribe(res => {
        this.game = res;
        this.loadImage();
      })
  }
  addToCart(game: any) {
    this._game.addToCart(game);
    this.gameAdded=`${game.name} added to cart.`;
  }

  loadImage(): void {
    this._game.GetGamesImages(this.game.id).subscribe(
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
}
