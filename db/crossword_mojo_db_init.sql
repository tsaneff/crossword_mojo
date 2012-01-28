-- Create DB:
use mysql;
create database crossword_proj character set utf8;

-- Create user:
grant all on crossword_proj.* to uzer identified by 'pazz';

use crossword_proj;

-- Create tables:
create table words
(
	id int unsigned not null auto_increment,
	primary key (id),
	word_len tinyint unsigned not null,
	word varchar (50) CHARACTER SET utf8 COLLATE utf8_general_ci not null
) DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;

create table descriptions
(
	word_id int unsigned not null,
	foreign key (word_id) references words(id) on update cascade on delete restrict,
	description varchar (1500) CHARACTER SET utf8 COLLATE utf8_general_ci not null
) DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;

-- Fill tables with data:
load data local infile 'BGN.words.dat'
into table words character set utf8 FIELDS TERMINATED BY '#' LINES TERMINATED BY '\r\n';

load data local infile 'BGN.descriptions.dat'
into table descriptions character set utf8 FIELDS TERMINATED BY '#' LINES TERMINATED BY '\r\n';
