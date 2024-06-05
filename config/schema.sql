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
       foreign key(account_id) references accounts(account_id) on delete cascade);

create index avatars_account_id on avatars(account_id);

create table finished_quests (
       avatar_id integer,
       quest_id text not null,
       completion_time integer not null,
       foreign key(avatar_id) references avatars(avatar_id) on delete cascade);

create index finished_quests_avatar_id on finished_quests(avatar_id);

create table tutorials_seen (
       avatar_id integer,
       tutorial_id text not null,
       foreign key(avatar_id) references avatars(avatar_id) on delete cascade);

create index tutorials_seen_avatar_id on tutorials_seen(avatar_id);
