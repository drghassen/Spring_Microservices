CREATE SEQUENCE category_seq
    START WITH 1
    INCREMENT BY 50
    MINVALUE 1
    NO MAXVALUE
    CACHE 1;

CREATE SEQUENCE games_seq
    START WITH 1
    INCREMENT BY 50
    MINVALUE 1
    NO MAXVALUE
    CACHE 1;

CREATE SEQUENCE orders_seq
    START WITH 1
    INCREMENT BY 50
    MINVALUE 1
    NO MAXVALUE
    CACHE 1;

CREATE SEQUENCE order_line_seq
    START WITH 1
    INCREMENT BY 50
    MINVALUE 1
    NO MAXVALUE
    CACHE 1;

CREATE SEQUENCE payment_seq
    START WITH 1
    INCREMENT BY 50
    MINVALUE 1
    NO MAXVALUE
    CACHE 1;

CREATE TABLE category (
    id integer NOT NULL,
    description varchar(255),
    name varchar(255),
    CONSTRAINT category_pkey PRIMARY KEY (id)
);

CREATE TABLE games (
    id integer NOT NULL,
    avaiblity double precision NOT NULL,
    description varchar(255),
    image varchar(255),
    name varchar(255),
    price double precision NOT NULL,
    category_id integer,
    CONSTRAINT games_pkey PRIMARY KEY (id)
);

CREATE TABLE orders (
    id integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    payment_method varchar(255),
    reference varchar(255),
    total_amount double precision NOT NULL,
    updated_at timestamp(6) without time zone,
    username varchar(255),
    CONSTRAINT orders_pkey PRIMARY KEY (id),
    CONSTRAINT orders_payment_method_check
        CHECK (payment_method IN ('PAYPAL', 'MASTERCARD', 'VISA'))
);

CREATE TABLE order_line (
    id integer NOT NULL,
    game_id integer,
    order_id integer,
    CONSTRAINT order_line_pkey PRIMARY KEY (id)
);

CREATE TABLE payment (
    id integer NOT NULL,
    amount double precision NOT NULL,
    created_date timestamp(6) without time zone NOT NULL,
    last_modified_date timestamp(6) without time zone,
    order_id integer,
    payment_method varchar(255),
    CONSTRAINT payment_pkey PRIMARY KEY (id),
    CONSTRAINT payment_payment_method_check
        CHECK (payment_method IN ('PAYPAL', 'VISA', 'MASTERCARD'))
);

ALTER TABLE games
    ADD CONSTRAINT fkhon03uf3jbtjm641g67orkhfi
    FOREIGN KEY (category_id) REFERENCES category(id);

ALTER TABLE order_line
    ADD CONSTRAINT fkk9f9t1tmkbq5w27u8rrjbxxg6
    FOREIGN KEY (order_id) REFERENCES orders(id);