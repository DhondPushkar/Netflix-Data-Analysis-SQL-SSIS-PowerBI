use SQL_Projects;
-- Create a duplicate of your raw table
SELECT *
INTO dbo.NetflixTitles_Cleaned
FROM dbo.NetflixTitles;

------------------------------------------------------------
-- STEP 2: Handle 'NULL' strings and actual NULL values
------------------------------------------------------------
UPDATE dbo.NetflixTitles_Cleaned
SET
    type        = NULLIF(LTRIM(RTRIM(type)), ''),
    title       = NULLIF(LTRIM(RTRIM(title)), ''),
    director    = NULLIF(LTRIM(RTRIM(director)), ''),
    cast        = NULLIF(LTRIM(RTRIM(cast)), ''),
    country     = NULLIF(LTRIM(RTRIM(country)), ''),
    date_added  = NULLIF(LTRIM(RTRIM(date_added)), ''),
    release_year= NULLIF(LTRIM(RTRIM(release_year)), ''),
    rating      = NULLIF(LTRIM(RTRIM(rating)), ''),
    duration    = NULLIF(LTRIM(RTRIM(duration)), ''),
    listed_in   = NULLIF(LTRIM(RTRIM(listed_in)), ''),
    description = NULLIF(LTRIM(RTRIM(description)), '');

-- Replace string 'NULL' values with real NULL
UPDATE dbo.NetflixTitles_Cleaned
SET
    type        = NULL WHERE type='NULL';
UPDATE dbo.NetflixTitles_Cleaned
SET
    director    = NULL WHERE director='NULL';
UPDATE dbo.NetflixTitles_Cleaned
SET
    cast        = NULL WHERE cast='NULL';
UPDATE dbo.NetflixTitles_Cleaned
SET
    country     = NULL WHERE country='NULL';
UPDATE dbo.NetflixTitles_Cleaned
SET
    date_added  = NULL WHERE date_added='NULL';
UPDATE dbo.NetflixTitles_Cleaned
SET
    rating      = NULL WHERE rating='NULL';
UPDATE dbo.NetflixTitles_Cleaned
SET
    duration    = NULL WHERE duration='NULL';
UPDATE dbo.NetflixTitles_Cleaned
SET
    listed_in   = NULL WHERE listed_in='NULL';
UPDATE dbo.NetflixTitles_Cleaned
SET
    description = NULL WHERE description='NULL';

------------------------------------------------------------
-- STEP 3: Replace NULL values with meaningful defaults
------------------------------------------------------------

UPDATE dbo.NetflixTitles_Cleaned SET type        = ISNULL(type, 'Unknown');
UPDATE dbo.NetflixTitles_Cleaned SET director    = ISNULL(director, 'Not Specified');
UPDATE dbo.NetflixTitles_Cleaned SET cast        = ISNULL(cast, 'Not Available');
UPDATE dbo.NetflixTitles_Cleaned SET country     = ISNULL(country, 'Unknown');
UPDATE dbo.NetflixTitles_Cleaned SET date_added  = ISNULL(date_added, 'Unknown');
UPDATE dbo.NetflixTitles_Cleaned SET rating      = ISNULL(rating, 'Unrated');
UPDATE dbo.NetflixTitles_Cleaned SET duration    = ISNULL(duration, 'Unknown');
UPDATE dbo.NetflixTitles_Cleaned SET listed_in   = ISNULL(listed_in, 'Miscellaneous');
UPDATE dbo.NetflixTitles_Cleaned SET description = ISNULL(description, 'Description Not Available');

------------------------------------------------------------
-- STEP 4: Convert 'release_year' to INT and handle NULLs
------------------------------------------------------------
ALTER TABLE dbo.NetflixTitles_Cleaned
ALTER COLUMN release_year INT;

-- DECLARE variable and set it, then UPDATE in the same batch
DECLARE @most_common_year INT;

SELECT TOP 1 
    @most_common_year = release_year
FROM dbo.NetflixTitles_Cleaned
WHERE release_year IS NOT NULL
GROUP BY release_year
ORDER BY COUNT(*) DESC;

PRINT 'Most common release year: ' + CAST(@most_common_year AS NVARCHAR(10));

UPDATE dbo.NetflixTitles_Cleaned
SET release_year = @most_common_year
WHERE release_year IS NULL;

-- verify
SELECT COUNT(*) AS Remaining_NULLs
FROM dbo.NetflixTitles_Cleaned
WHERE release_year IS NULL;



------------------------------------------------------------
-- STEP 5: Clean 'duration' and split into minutes / seasons
------------------------------------------------------------

-- Add columns safely
IF COL_LENGTH('dbo.NetflixTitles_Cleaned', 'duration_minutes') IS NULL
    ALTER TABLE dbo.NetflixTitles_Cleaned ADD duration_minutes INT;

IF COL_LENGTH('dbo.NetflixTitles_Cleaned', 'duration_seasons') IS NULL
    ALTER TABLE dbo.NetflixTitles_Cleaned ADD duration_seasons INT;

-- Extract numeric value and assign based on type
UPDATE dbo.NetflixTitles_Cleaned
SET duration_minutes = TRY_CAST(LEFT(duration, CHARINDEX(' ', duration + ' ') - 1) AS INT)
WHERE duration LIKE '%min%';

UPDATE dbo.NetflixTitles_Cleaned
SET duration_seasons = TRY_CAST(LEFT(duration, CHARINDEX(' ', duration + ' ') - 1) AS INT)
WHERE duration LIKE '%Season%';

-- Replace NULL numeric values with most frequent numeric values
DECLARE @common_duration_minutes INT, @common_duration_seasons INT;

SELECT TOP 1 @common_duration_minutes = duration_minutes
FROM dbo.NetflixTitles_Cleaned
WHERE duration_minutes IS NOT NULL
GROUP BY duration_minutes
ORDER BY COUNT(*) DESC;

SELECT TOP 1 @common_duration_seasons = duration_seasons
FROM dbo.NetflixTitles_Cleaned
WHERE duration_seasons IS NOT NULL
GROUP BY duration_seasons
ORDER BY COUNT(*) DESC;

UPDATE dbo.NetflixTitles_Cleaned
SET duration_minutes = ISNULL(duration_minutes, @common_duration_minutes),
    duration_seasons = ISNULL(duration_seasons, @common_duration_seasons);

------------------------------------------------------------
-- STEP 6: Handle Date column properly
------------------------------------------------------------
-- Convert 'date_added' to DATE type safely
ALTER TABLE dbo.NetflixTitles_Cleaned
ADD date_added_clean DATE;

UPDATE dbo.NetflixTitles_Cleaned
SET date_added_clean = TRY_CONVERT(DATE, date_added);

-- Replace invalid or NULL dates with default earliest available
DECLARE @earliest_date DATE;
SELECT @earliest_date = MIN(date_added_clean) FROM dbo.NetflixTitles_Cleaned WHERE date_added_clean IS NOT NULL;

UPDATE dbo.NetflixTitles_Cleaned
SET date_added_clean = ISNULL(date_added_clean, @earliest_date);

------------------------------------------------------------
-- STEP 7: Remove duplicates
------------------------------------------------------------
;WITH CTE AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY title, type, release_year ORDER BY show_id) AS rn
    FROM dbo.NetflixTitles_Cleaned
)
DELETE FROM CTE WHERE rn > 1;

------------------------------------------------------------
-- STEP 8: Create Split Tables (Normalized)
------------------------------------------------------------

-- 1️⃣ Actors
IF OBJECT_ID('dbo.NetflixActors', 'U') IS NOT NULL DROP TABLE dbo.NetflixActors;
SELECT DISTINCT
    show_id,
    TRIM(value) AS actor
INTO dbo.NetflixActors
FROM dbo.NetflixTitles_Cleaned
CROSS APPLY STRING_SPLIT(cast, ',')
WHERE cast IS NOT NULL AND TRIM(value) <> '';

-- 2️⃣ Countries
IF OBJECT_ID('dbo.NetflixCountries', 'U') IS NOT NULL DROP TABLE dbo.NetflixCountries;
SELECT DISTINCT
    show_id,
    TRIM(value) AS country
INTO dbo.NetflixCountries
FROM dbo.NetflixTitles_Cleaned
CROSS APPLY STRING_SPLIT(country, ',')
WHERE country IS NOT NULL AND TRIM(value) <> '';

-- 3️⃣ Genres
IF OBJECT_ID('dbo.NetflixGenres', 'U') IS NOT NULL DROP TABLE dbo.NetflixGenres;
SELECT DISTINCT
    show_id,
    TRIM(value) AS genre
INTO dbo.NetflixGenres
FROM dbo.NetflixTitles_Cleaned
CROSS APPLY STRING_SPLIT(listed_in, ',')
WHERE listed_in IS NOT NULL AND TRIM(value) <> '';

------------------------------------------------------------
-- STEP 9: Verify data consistency
------------------------------------------------------------
SELECT COUNT(*) AS TotalRows FROM dbo.NetflixTitles_Cleaned;
SELECT COUNT(DISTINCT show_id) AS UniqueShowIDs FROM dbo.NetflixTitles_Cleaned;

SELECT * FROM dbo.NetflixTitles_Cleaned WHERE title IS NULL OR title='';

------------------------------------------------------------
-- ✅ CLEAN DATASET READY FOR POWER BI IMPORT ✅
------------------------------------------------------------




-- Netflix Data Analysis --
---------------------------

select * from NetflixTitles;

select  count(*) as total_content from NetflixTitles;

select distinct type from NetflixTitles;

-- 1. Count the number of Movies vs TV Shows
select type, 
count(*) as total_content
from NetflixTitles 
group by type;

-- 2. Find the most common rating for movies and TV shows
select 
type,
rating
from
(select 
       type,
       rating,
       count(*) as count_of_rating,
	   rank() over(Partition by type order by count(*) desc) as ranking
from NetflixTitles
group by type, rating) as t1
where 
     ranking = 1;

-- 3. List all movies released in a specific year (e.g., 2020)
select * from NetflixTitles
where
     type = 'Movie'
	 and
	 release_year = 2020;

-- 4. Find the top 5 countries with the most content on Netflix


SELECT TOP 5
    TRIM(value) AS country,
    COUNT(*) AS total_content
FROM NetflixTitles
CROSS APPLY STRING_SPLIT(country, ',')
WHERE country IS NOT NULL 
    AND TRIM(country) != ''
    AND TRIM(value) != ''
GROUP BY TRIM(value)
ORDER BY total_content DESC;


-- 5. Identify the longest movie

select * from NetflixTitles
where 
     type = 'Movie'
	 AND
	 duration = (select max(duration) from NetflixTitles)

-- 6. Find content added in the last 5 years
SELECT *
FROM NetflixTitles
WHERE 
    date_added IS NOT NULL
    AND TRY_CONVERT(DATE, date_added, 107) >= DATEADD(YEAR, -5, GETDATE());

-- 7. Find all the movies/TV shows by director 'Rajiv Chilaka'
select *
from NetflixTitles
where director like '%Rajiv Chilaka%';

-- 8. List all TV shows with more than 5 seasons
SELECT *
FROM NetflixTitles
WHERE 
    type = 'TV Show'
    AND
    CAST(SUBSTRING(duration, 1, CHARINDEX(' ', duration + ' ') - 1) AS INT) > 5;

-- 9. Count the number of content items in each genre
SELECT 
    TRIM(value) AS genre,
    COUNT(*) AS count_of_content
FROM NetflixTitles
CROSS APPLY STRING_SPLIT(listed_in, ',')
WHERE listed_in IS NOT NULL
GROUP BY TRIM(value)
ORDER BY count_of_content DESC;


-- 10. Find each year and the average numbers of content release in India on Netflix. 
-- Return top 5 year with highest avg content release.

SELECT TOP 5
    YEAR(TRY_CONVERT(DATE, date_added, 107)) AS release_year,
    COUNT(*) AS total_content,
    CAST(COUNT(*) AS FLOAT) / 12 AS avg_content_per_month
FROM NetflixTitles
CROSS APPLY STRING_SPLIT(country, ',')
WHERE 
    TRIM(value) = 'India'
    AND date_added IS NOT NULL
GROUP BY YEAR(TRY_CONVERT(DATE, date_added, 107))
ORDER BY total_content DESC;

-- 11. List all movies that are documentaries

SELECT 
    type,
    listed_in
FROM NetflixTitles
CROSS APPLY STRING_SPLIT(listed_in, ',')
WHERE 
    TRIM(value) = 'Documentaries'
    AND type = 'Movie';

-- 12. Find all content without a director
SELECT *
FROM NetflixTitles
WHERE 
    director IS NULL 
    OR TRIM(director) = '';

-- 13. Find how many movies actor 'Salman Khan' appeared in last 10 years.

SELECT *
FROM NetflixTitles
CROSS APPLY STRING_SPLIT(cast, ',')
WHERE 
    type = 'Movie'
    AND TRIM(value) LIKE '%Salman Khan%'
    AND release_year >= YEAR(GETDATE()) - 10;


-- 14. Find the top 10 actors who have appeared in the highest number of movies produced in India.

SELECT TOP 10
    TRIM(actor_split.value) AS actor_name,
    COUNT(DISTINCT show_id) AS movie_count
FROM NetflixTitles
CROSS APPLY STRING_SPLIT(country, ',') AS country_split
CROSS APPLY STRING_SPLIT(cast, ',') AS actor_split
WHERE 
    type = 'Movie'
    AND TRIM(country_split.value) = 'India'
    AND cast IS NOT NULL
    AND TRIM(actor_split.value) != ''
GROUP BY TRIM(actor_split.value)
ORDER BY movie_count DESC;

-- 15.Categorize the content based on the presence of the keywords 'kill' and 'violence' in 
-- the description field. Label content containing these keywords as 'Bad' and all other 
-- content as 'Good'. Count how many items fall into each category.

WITH CategorizedContent AS (
    SELECT 
        CASE 
            WHEN description LIKE '%kill%' OR description LIKE '%violence%' THEN 'Bad'
            ELSE 'Good'
        END AS category
    FROM NetflixTitles
)
SELECT 
    category,
    COUNT(*) AS content_count
FROM CategorizedContent
GROUP BY category;

