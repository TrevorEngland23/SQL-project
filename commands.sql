-- Business Question: "During the summer months (June 1 - August 31) for the available data, what were the top three genres that customers rented?"

-- Summary Table Query
SELECT cat.name AS genre, COUNT(r.rental_id) AS rental_count
FROM rental AS r
INNER JOIN inventory AS i ON r.inventory_id = i.inventory_id
INNER JOIN film AS f ON i.film_id = f.film_id
INNER JOIN film_category AS fc ON f.film_id = fc.film_id
INNER JOIN category AS cat ON fc.category_id = cat.category_id
WHERE r.rental_date BETWEEN '2005-06-01' AND '2005-09-01'
GROUP BY cat.name
ORDER BY rental_count DESC
LIMIT 3;


-- Detail Table Query
SELECT r.rental_date, cust.first_name, cust.last_name, f.title AS movie, cat.name AS genre
FROM rental AS r
INNER JOIN inventory AS i ON r.inventory_id = i.inventory_id
INNER JOIN film AS f ON i.film_id = f.film_id
INNER JOIN film_category AS fc ON f.film_id = fc.film_id
INNER JOIN category AS cat ON fc.category_id = cat.category_id
INNER JOIN customer as cust ON r.customer_id = cust.customer_id
WHERE r.rental_date BETWEEN '2005-06-01' AND '2005-09-01'
AND cat.name IN ('Sports', 'Animation', 'Sci-Fi') 
-- here we may be able to create a function that populates the data based on the the summary table
ORDER BY r.rental_date DESC;

-- User defined function on first and last name columns.
CREATE OR REPLACE FUNCTION get_customer_name(first_name VARCHAR(45), last_name VARCHAR(45))
RETURNS VARCHAR(60) AS $$
BEGIN
	IF first_name IS NULL AND last_name IS NULL THEN
		RETURN 'N/A';
	ELSEIF first_name IS NULL THEN 
		RETURN TRIM(last_name);
	ELSEIF last_name IS NULL THEN
		RETURN TRIM(first_name);
	ELSE 
		RETURN TRIM(first_name) || ' ' || TRIM(last_name);
	END IF;
END;
$$ LANGUAGE plpgsql

-- User Defined Function for dynamically populating detailed table with top three genres from the summary table
CREATE OR REPLACE FUNCTION get_top_three_genres()
RETURNS VARCHAR[] AS $$
DECLARE
	top_three_genres_list VARCHAR[];
BEGIN
	SELECT array_agg(cat.name)
	INTO top_three_genres_list
	FROM (
		SELECT rs.genre, rs.total_rentals
		FROM rental_summary AS rs
		ORDER BY rs.total_rentals DESC
		LIMIT 3
	) AS top_three_genres
	INNER JOIN category AS cat ON top_three_genres.genre = cat.name;

	RETURN top_three_genres_list;
END;
$$ LANGUAGE plpgsql;


-- Create summary table
CREATE TABLE rental_summary (
genre VARCHAR(25),
total_rentals INTEGER
);

-- Create detailed table
CREATE TABLE rental_details(
rental_id SERIAL PRIMARY KEY,
rental_date TIMESTAMP,
customer_id INTEGER,
customer_name VARCHAR(60),
movie_title VARCHAR(255),
genre VARCHAR(25),
film_id INTEGER,
category_id INTEGER,
FOREIGN KEY(customer_id) REFERENCES customer(customer_id),
FOREIGN KEY(film_id) REFERENCES film(film_id),
FOREIGN KEY(category_id) REFERENCES category(category_id)
);

-- Populate rental_summary
INSERT INTO rental_summary(genre, total_rentals)
SELECT cat.name AS genre, COUNT(r.rental_id) AS rental_count
FROM rental AS r
INNER JOIN inventory AS i ON r.inventory_id = i.inventory_id
INNER JOIN film AS f ON i.film_id = f.film_id
INNER JOIN film_category AS fc ON f.film_id = fc.film_id
INNER JOIN category AS cat ON fc.category_id = cat.category_id
WHERE r.rental_date BETWEEN '2005-06-01' AND '2005-09-01'
GROUP BY cat.name
ORDER BY rental_count DESC
LIMIT 3;



-- Populate rental_details
INSERT INTO rental_details
SELECT r.rental_id, r.rental_date, cust.customer_id, get_customer_name(cust.first_name, cust.last_name) AS customer_name, f.title AS movie_title, cat.name AS genre, f.film_id, cat.category_id
FROM rental AS r
INNER JOIN inventory AS i ON r.inventory_id = i.inventory_id
INNER JOIN film AS f ON i.film_id = f.film_id
INNER JOIN film_category AS fc ON f.film_id = fc.film_id
INNER JOIN category AS cat ON fc.category_id = cat.category_id
INNER JOIN customer as cust ON r.customer_id = cust.customer_id
WHERE r.rental_date BETWEEN '2005-06-01' AND '2005-09-01'
AND cat.name IN (SELECT unnest(get_top_three_genres()))
ORDER BY r.rental_date DESC;

-- here down, probably gut it and restart

-- Trigger to continually update the summary table as data is added to the detail table
CREATE OR REPLACE FUNCTION update_rental_summary()
RETURNS TRIGGER AS $$
BEGIN
    -- Check if the genre already exists in the summary table
    IF EXISTS (
        SELECT 1 FROM rental_summary WHERE genre = NEW.genre
    ) THEN
        -- Increment the total_rentals for the existing genre
        UPDATE rental_summary
        SET total_rentals = total_rentals + 1
        WHERE genre = NEW.genre;
    ELSE
        -- Insert a new row for the genre if it does not exist
        INSERT INTO rental_summary (genre, total_rentals)
        VALUES (NEW.genre, 1);
    END IF;

    RETURN NULL; -- The trigger does not need to return anything
END;
$$ LANGUAGE plpgsql;

-- Create the trigger for adding data to rental detail
CREATE TRIGGER trg_update_summary_insert
AFTER INSERT ON rental_details
FOR EACH ROW
EXECUTE FUNCTION update_rental_summary();

-- Trigger for removing data from the detailed table (mostly for troubleshooting)
CREATE OR REPLACE FUNCTION update_rental_summary_on_delete()
RETURNS TRIGGER AS $$
BEGIN
    -- Check if the genre exists in the summary table
    IF EXISTS (
        SELECT 1 FROM rental_summary WHERE genre = OLD.genre
    ) THEN
        -- Decrement the total_rentals for the genre
        UPDATE rental_summary
        SET total_rentals = total_rentals - 1
        WHERE genre = OLD.genre;

        -- If total_rentals reaches 0, delete the genre entry from the summary table
        DELETE FROM rental_summary
        WHERE genre = OLD.genre AND total_rentals <= 0;
    END IF;

    RETURN NULL; -- The trigger does not need to return anything
END;
$$ LANGUAGE plpgsql;

-- Create the trigger for deleting data 
CREATE TRIGGER trg_update_summary_delete
AFTER DELETE ON rental_details
FOR EACH ROW
EXECUTE FUNCTION update_rental_summary_on_delete();





-- Troubleshooting Queries
INSERT INTO rental_details (rental_date, customer_id, customer_name, movie_title, genre, film_id, category_id)
VALUES (
    '2005-07-01 14:30:00',
    131,                    -- customer_id (should exist in the customer table)
    'Monica Hicks',             -- customer_name
    'River Outlaw',         -- movie_title
    'Sports',               -- genre
    733,                    -- film_id (should exist in the film table)
    15                      -- category_id (should exist in the category table)
);

DELETE FROM rental_details
WHERE rental_date = '2005-07-01 14:30:00'
  AND customer_id = 131
  AND movie_title = 'River Outlaw';

SELECT * 
FROM rental_details
WHERE customer_id = 131;


SELECT * FROM rental_summary
SELECT * FROM rental_details
SELECT COUNT(rental_id) FROM rental_details
DELETE FROM rental_details;
DROP TABLE rental_details;
DROP TABLE rental_summary