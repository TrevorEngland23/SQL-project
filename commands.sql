-- Business Question: "During the summer months (June 1 - August 31) for the available data, what were the top three genres that customers rented?"



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
    SELECT array_agg(genre)
    INTO top_three_genres_list
    FROM (
        SELECT cat.name AS genre, COUNT(r.rental_id) AS rental_count
        FROM rental AS r
        INNER JOIN inventory AS i ON r.inventory_id = i.inventory_id
        INNER JOIN film AS f ON i.film_id = f.film_id
        INNER JOIN film_category AS fc ON f.film_id = fc.film_id
        INNER JOIN category AS cat ON fc.category_id = cat.category_id
        WHERE r.rental_date BETWEEN '2005-06-01' AND '2005-09-01'
        GROUP BY cat.name
        ORDER BY rental_count DESC
        LIMIT 3
    ) AS top_genres;

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

-- Update the summary table when the detail table is updated with new data
CREATE OR REPLACE FUNCTION update_summary()
RETURNS TRIGGER
AS $$
BEGIN
	DELETE FROM rental_summary;

	INSERT INTO rental_summary
	SELECT genre, COUNT(rental_id) AS rental_count
	FROM rental_details
	GROUP BY genre
	ORDER BY rental_count DESC;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create the trigger 
CREATE TRIGGER auto_summary
AFTER INSERT
ON rental_details
FOR EACH STATEMENT
EXECUTE PROCEDURE update_summary();

-- Update the summary table when data is deleted from the detail table (mainly for troubleshooting)
CREATE OR REPLACE FUNCTION update_summary_on_delete()
RETURNS TRIGGER
AS $$
BEGIN
    DELETE FROM rental_summary;

    INSERT INTO rental_summary
    SELECT genre, COUNT(rental_id) AS rental_count
    FROM rental_details
    GROUP BY genre
    ORDER BY rental_count DESC;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- Create the trigger
CREATE TRIGGER auto_summary_delete
AFTER DELETE
ON rental_details
FOR EACH STATEMENT
EXECUTE PROCEDURE update_summary_on_delete();

-- Create procedure to refresh table data
CREATE OR REPLACE PROCEDURE refresh_summary_and_details()
AS $$
BEGIN
	DELETE FROM rental_details;

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
	RETURN;
END;
$$ LANGUAGE plpgsql;

-- Call the procedure
CALL refresh_summary_and_details();

-- Troubleshooting Queries ---------------------------------------------------------
INSERT INTO rental (rental_date, inventory_id, customer_id, return_date, staff_id)
VALUES (
    '2005-06-23',
    130,
    85,
    '2005-07-01',
    2 
);

SELECT DISTINCT i.inventory_id
FROM inventory AS i
INNER JOIN film AS f ON i.film_id = f.film_id
INNER JOIN film_category AS fc ON f.film_id = fc.film_id
INNER JOIN category AS cat ON fc.category_id = cat.category_id
WHERE cat.name IN (
    SELECT genre
    FROM rental_summary
)
ORDER BY i.inventory_id;


SELECT * FROM inventory



SELECT * FROM rental
WHERE customer_id = 85 AND inventory_id = 152;

DELETE FROM rental
WHERE customer_id = 85 AND inventory_id = 152;

SELECT * FROM rental_summary
SELECT * FROM rental_details

SELECT * FROM rental_details
WHERE customer_id = 85 

SELECT COUNT(rental_id) FROM rental_details
DELETE FROM rental_details;
DROP TABLE rental_details;
DROP TABLE rental_summary

-- QUERIES FROM THE BEGINNING

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

