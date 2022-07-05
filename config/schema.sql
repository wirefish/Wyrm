create table accounts (
       account_id integer primary key,
       username text not null,
       password_key blob not null,
       salt blob not null,
       created text default current_timestamp,
       last_login text default current_timestamp);

create unique index accounts_username on accounts(username);

create table avatars (
       avatar_id integer primary key,
       account_id integer not null,
       avatar blob not null,
       aliases blob default null,
       settings blob default null,
       created text default current_timestamp,
       foreign key(account_id) references accounts(account_id));

create index avatars_account_id on avatars(account_id);
