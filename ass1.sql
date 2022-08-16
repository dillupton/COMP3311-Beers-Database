-- COMP3311 21T3 Assignment 1
-- z5308844

-- Fill in the gaps ("...") below with your code
-- You can add any auxiliary views/function that you like
-- The code in this file MUST load into a database in one pass
-- It will be tested as follows:
-- createdb test; psql test -f ass1.dump; psql test -f ass1.sql
-- Make sure it can load without errorunder these conditions


-- Q1: oldest brewery

create or replace view Q1(brewery)
as
	SELECT name
	FROM breweries
	WHERE founded = (SELECT min(founded) FROM breweries)
;

-- Q2: collaboration beers

create or replace view Q2(beer)
as
	SELECT beers.name
	FROM brewed_by b1
	JOIN brewed_by b2 ON b1.beer = b2.beer 
	AND b1.brewery <> b2.brewery
	JOIN beers ON b1.beer = beers.id
	GROUP BY beers.name
	HAVING count(*) > 1
;

-- Q3: worst beer

create or replace view Q3(worst)
as
	SELECT name 
	FROM beers
	WHERE rating = (SELECT min(rating) FROM beers)
;

-- Q4: too strong beer

create or replace view Q4(beer,abv,style,max_abv)
as
	SELECT beers.name, beers.abv, styles.name, styles.max_abv
	FROM beers
	JOIN styles ON beers.style = styles.id
	WHERE beers.abv > styles.max_abv
;

-- Q5: most common style

create or replace view Q5(style)
as
	SELECT styles.name
	FROM styles
	JOIN beers ON beers.style = styles.id
	GROUP BY styles.name
	HAVING count(*) = 	-- matches count to the max count (meaning most common style)	
	(
		SELECT max(COUNTER)
		FROM (
			SELECT count(*) AS COUNTER
			FROM beers
			JOIN styles ON beers.style = styles.id
			GROUP BY styles.name
		) AS POP
	)
;

-- Q6: duplicated style names

create or replace view Q6(style1,style2)
as
	SELECT s1.name, s2.name
	FROM styles s1
	JOIN styles s2 ON LOWER(s1.name) = LOWER(s2.name)
	AND s1.name < s2.name
;

-- Q7: breweries that make no beers

create or replace view Q7(brewery)
as
	SELECT breweries.name
	FROM breweries
	LEFT OUTER JOIN brewed_by ON breweries.id = brewed_by.brewery
	WHERE brewed_by.beer IS NULL
;

-- Q8: city with the most breweries

create or replace view Q8(city,country)
as
	SELECT locations.metro, locations.country
	FROM breweries
	JOIN locations ON breweries.located_in = locations.id
	GROUP BY locations.metro, locations.country
	HAVING count(*) = 	-- similar to most common style (most common breweries)
	(
		SELECT max(COUNTER)
		FROM (
			SELECT locations.metro, locations.country, count(*) AS COUNTER
			FROM breweries
			JOIN locations ON breweries.located_in = locations.id
			WHERE locations.metro IS NOT NULL AND locations.country IS NOT NULL
			GROUP BY locations.metro, locations.country
			
		) AS MaxLoc
	)
;

-- Q9: breweries that make more than 5 styles
create or replace view Q9(brewery,nstyles)
as
	SELECT breweries.name, count(DISTINCT beers.style) AS nstyles
	FROM breweries 
	JOIN brewed_by ON breweries.id = brewed_by.brewery
	JOIN beers ON brewed_by.beer = beers.id
	GROUP BY breweries.name
	HAVING count(DISTINCT beers.style) > 5
;


-- Q10: beers of a certain style

create or replace view 
BeerInfo (beer, brewery, _style, year, abv)
as
	SELECT b.name, string_agg(br.name,' + ' ORDER BY br.name ASC), s.name, b.brewed, b.abv
	FROM beers b
	JOIN brewed_by ON b.id = brewed_by.beer
	JOIN breweries br ON brewed_by.brewery = br.id
	JOIN styles s ON b.style = s.id
	GROUP BY b.name, s.name, b.brewed, b.abv, brewed_by.beer;
; 

create or replace function
	q10(_style text) returns setof BeerInfo
as $$
begin
	RETURN QUERY
	SELECT b.name, string_agg(br.name,' + ' ORDER BY br.name ASC), s.name, b.brewed, b.abv 
	FROM beers b
	JOIN brewed_by ON b.id = brewed_by.beer
	JOIN breweries br ON brewed_by.brewery = br.id
	JOIN styles s ON b.style = s.id
	WHERE s.name = $1
	GROUP BY b.name, s.name, b.brewed, b.abv, brewed_by.beer;
end;
$$
language plpgsql;

-- Q11: beers with names matching a pattern

create or replace function
	Q11(partial_name text) returns setof text
as $$
begin
	RETURN QUERY
	SELECT quote_ident(b.name) || ', ' || string_agg(br.name,' + ' ORDER BY br.name ASC) || ', ' || s.name || ', ' || b.abv || '% ABV'
	FROM beers b
	JOIN brewed_by ON b.id = brewed_by.beer
	JOIN breweries br ON brewed_by.brewery = br.id
	JOIN styles s ON b.style = s.id
	WHERE LOWER(b.name) ~ LOWER($1)
	GROUP BY b.name, s.name, b.abv, brewed_by.beer;	
end;
$$
language plpgsql;

-- Q12: breweries and the beers they make

-- helper to return location info for when specific fields are null
create or replace function
	locationInfo(breweryID integer) returns text
as $$
declare 
	town text;
	metro text;
	region text;
	country text;
begin
	SELECT l.town, l.metro, l.region, l.country into town, metro, region, country
	FROM locations l
	WHERE l.id = $1;
	
	-- filter out what is null and not null to alter return
	if town is not null then
		if region is not null then
			return town || ', ' || region || ', ' || country;
		else
			return town || ', ' || country;
		end if;
	else
		if region is not null then
			return metro || ', ' || region || ', ' || country;
		else
			return metro || ', ' || country;
		end if;
	end if;
	
end;
$$
language plpgsql;



create or replace function
	Q12(partial_name text) returns setof text
as $$
declare 
	tuple record;
begin
	for tuple in 
		SELECT * 
		FROM breweries br
		WHERE lower(br.name) ~ lower($1)
		ORDER BY br.name asc
	loop
		return next tuple.name || ', founded ' || tuple.founded;
		
		return QUERY
		SELECT 'located in ' || locationInfo(br.located_in)
		FROM breweries br
		WHERE br.id = tuple.id;	
		
		-- at least one beer found
		if (SELECT brewed_by.beer from brewed_by where brewed_by.brewery = tuple.id limit 1) is not null then
			return query
			SELECT '  ' || quote_ident(b.name) || ', ' || s.name || ', ' || b.brewed || ', ' || b.abv || '% ABV'
			FROM beers b
			JOIN brewed_by ON b.id = brewed_by.beer
			JOIN breweries br ON brewed_by.brewery = br.id
			JOIN styles s ON b.style = s.id
			WHERE brewed_by.brewery = tuple.id
			ORDER BY b.brewed asc, b.name asc;
		else
			return next '  No Known Beers';
		end if;
	end loop;
end;
$$
language plpgsql;