* Анализ рынка жилой недвижимости Санкт-Петербурга и Ленинградской области

-- Фильтрация данных от аномальных значений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдем id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    )
-- Выведем объявления без выбросов:
SELECT *
FROM real_estate.flats
WHERE id IN (SELECT * FROM filtered_id);


-- Задача 1: Время активности объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. Какие сегменты рынка недвижимости Санкт-Петербурга и городов Ленинградской области 
--    имеют наиболее короткие или длинные сроки активности объявлений?
-- 2. Какие характеристики недвижимости, включая площадь недвижимости, среднюю стоимость квадратного метра, 
--    количество комнат и балконов и другие параметры, влияют на время активности объявлений? 
--    Как эти зависимости варьируют между регионами?
-- 3. Есть ли различия между недвижимостью Санкт-Петербурга и Ленинградской области по полученным результатам?

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit, -- все что больше 99 перцентиля будет отсечено 
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l -- все что меньше 1 перцентиля будет отсечено
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats AS f
    LEFT JOIN real_estate.TYPE AS t USING (type_id)
    WHERE -- используя подзапрос в WHERE отфильтруем объявления с аномальными значениями
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    AND t.TYPE = 'город'
    ),
category AS (-- Выведем объявления без выбросов и разобьем по категориям:
SELECT 
	CASE
		WHEN c.city = 'Санкт-Петербург'
			THEN 'Санкт-Петербург'
		ELSE 'Ленинградская обл'
	END AS region,
	CASE
		WHEN a.days_exposition BETWEEN 1 AND 30
			THEN 'до месяца'
		WHEN a.days_exposition BETWEEN 31and 90
			THEN 'до квартала'
		WHEN a.days_exposition BETWEEN 91 AND 180
			THEN 'до полугода'
		WHEN a.days_exposition > 181
			THEN 'более полугода'
	END AS activity_segment,	
	*-- выгружаем все значения из таблицы flats
	FROM real_estate.flats AS f 
	LEFT JOIN real_estate.city AS c USING (city_id)
	LEFT JOIN real_estate.advertisement AS a USING (id)
	WHERE id IN (SELECT * FROM filtered_id)-- подзапрос в WHERE выведет все объявления без выбросов
)
SELECT 
	region,
	activity_segment,
	COUNT (*) AS number_of_ads, -- количество объявлений
	ROUND (AVG(last_price/total_area)::numeric,2) AS avg_square_meter, -- средняя стоимость кв.метра
	ROUND (AVG (total_area)::NUMERIC,2) AS avg_area, -- средняя площадь
	ROUND (SUM (open_plan)::NUMERIC/COUNT (open_plan),5) AS pes_open_plan, -- доля студий
	ROUND (SUM (is_apartment)::NUMERIC/COUNT (is_apartment),4) AS per_apartment, -- доля апартаментов
	ROUND (AVG (airports_nearest)::NUMERIC/1000,2) AS avg_distance_air, -- среднее расстояние до аэропорта
	PERCENTILE_DISC (0.5) WITHIN GROUP (ORDER BY airports_nearest )AS median_distance_air, -- медиана до аэропорта
	ROUND (AVG (parks_around3000::NUMERIC),2) AS avg_parks_around, -- среднее число парков
	PERCENTILE_DISC (0.5) WITHIN GROUP (ORDER BY parks_around3000) AS median_parks_around, -- медиана до парков
	ROUND (AVG (ponds_around3000)::NUMERIC,2) AS avg_ponds_around, -- среднее число водоемов
	PERCENTILE_DISC (0.5) WITHIN GROUP (ORDER BY ponds_around3000) AS median_ponds_around, -- медиана до водоемов
	ROUND(COUNT(id) * 100.0 / SUM(COUNT(id)) OVER (PARTITION BY region),2) AS perc_ads_region, -- доля объявлений в разрезе региона
	ROUND(COUNT(id) * 100.0 / SUM(COUNT(id)) OVER (PARTITION BY activity_segment),2) AS perc_ads_segment -- Доля объявлений в разрезе сегмента
FROM category
WHERE activity_segment IS NOT NULL
GROUP BY region ,activity_segment
ORDER BY region DESC 

-- Задача 2: Сезонность объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
--    А в какие — по снятию? Это показывает динамику активности покупателей.
-- 2. Совпадают ли периоды активной публикации объявлений и периоды, 
--    когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений)?
-- 3. Как сезонные колебания влияют на среднюю стоимость квадратного метра и среднюю площадь квартир? 
--    Что можно сказать о зависимости этих параметров от месяца?

-- Анализ по публикациям
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats
    LEFT JOIN real_estate.TYPE AS t USING (type_id)
    LEFT JOIN real_estate.advertisement AS a USING (id)
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
        AND t.TYPE = 'город'
        AND a.first_day_exposition BETWEEN '2015-01-01' AND '2018-12-31'  -- Фильтр по годам
    ),
extract_month AS (
    SELECT 
        EXTRACT(MONTH FROM (a.first_day_exposition)) AS first_month_exposition,
        COUNT (*) AS number_of_ads,
        ROUND(AVG(a.last_price/f.total_area)::numeric,2) AS avg_cost_square_meter,
        ROUND(AVG(total_area)::NUMERIC,2) AS avg_area
    FROM real_estate.flats AS f
    LEFT JOIN real_estate.advertisement AS a USING (id)
    WHERE id IN (SELECT * FROM filtered_id)
    GROUP BY first_month_exposition
)
SELECT
    ROW_NUMBER() OVER(ORDER BY number_of_ads DESC) AS row_num,
    *
FROM extract_month

-- Анализ по снятию объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit, -- все что больше 99 перцентиля будет отсечено 
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l -- все что меньше 1 перцентиля будет отсечено
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats
    LEFT JOIN real_estate.TYPE AS t USING (type_id)
    LEFT JOIN real_estate.advertisement AS a USING (id)
    WHERE -- используя подзапрос в WHERE отфильтруем объявления с аномальными значениями
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
        AND t.TYPE = 'город'
        AND a.first_day_exposition BETWEEN '2015-01-01' AND '2018-12-31'  -- Фильтр по годам
    ),
extract_month AS (-- Выведем снятые объявления без выбросов с извлечением номера месяца, средней стоиомстью за кв. метр и средней площадью:
	SELECT 
		EXTRACT (MONTH FROM ( a.first_day_exposition + (a.days_exposition ||'days')::INTERVAL)) AS last_month_exposition,
		COUNT (f.id) AS number_of_ads,
		ROUND (AVG(a.last_price/f.total_area)::numeric,2) AS avg_cost_square_meter,
		ROUND (AVG (total_area)::NUMERIC,2) AS avg_area
	FROM real_estate.flats AS f
	LEFT JOIN real_estate.advertisement AS a USING (id)
	WHERE id IN (SELECT * FROM filtered_id) AND a.days_exposition IS NOT NULL
	GROUP BY last_month_exposition
)
SELECT
	ROW_NUMBER() OVER(ORDER BY number_of_ads DESC) AS row_num,
	*
FROM extract_month


-- Задача 3: Анализ рынка недвижимости Ленобласти
-- Результат запроса должен ответить на такие вопросы:
-- 1. В каких населённые пунктах Ленинградской области наиболее активно публикуют объявления о продаже недвижимости?
-- 2. В каких населённых пунктах Ленинградской области — самая высокая доля снятых с публикации объявлений? 
--    Это может указывать на высокую долю продажи недвижимости.
-- 3. Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир в различных населённых пунктах? 
--    Есть ли вариация значений по этим метрикам?
-- 4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? 
--    То есть где недвижимость продаётся быстрее, а где — медленнее.

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit, -- все что больше 99 перцентиля будет отсечено 
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l -- все что меньше 1 перцентиля будет отсечено
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE -- используя подзапрос в WHERE отфильтруем объявления с аномальными значениями
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    )
	SELECT 
		c.city AS city,
		t.TYPE AS type,
		COUNT (*) AS count_ads, -- количество объявлений
		ROUND(COUNT (*) FILTER (WHERE a.days_exposition IS NOT NULL)::numeric / COUNT (*)*100,2) AS perc_removed_ads, -- доля снятых объявлений
		ROUND(AVG (a.last_price::NUMERIC/f.total_area::NUMERIC),2) AS avg_square_meter, -- cредняя стоимость кв.метра
		ROUND(AVG (f.total_area)::NUMERIC,2) AS avg_area -- Средняя площадь
	FROM real_estate.flats AS f
	LEFT JOIN real_estate.city AS c USING (city_id)
	LEFT JOIN real_estate.TYPE AS t USING (type_id)
	LEFT JOIN real_estate.advertisement AS a USING (id)
	WHERE id IN (SELECT * FROM filtered_id) AND c.city <> 'Санкт-Петербург'
	GROUP BY c.city, t.TYPE
	HAVING COUNT(*) > 100
	ORDER BY avg_area DESC 
	
-- Отдельно по Кудрово
	-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit, -- все что больше 99 перцентиля будет отсечено 
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l -- все что меньше 1 перцентиля будет отсечено
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE -- используя подзапрос в WHERE отфильтруем объявления с аномальными значениями
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    )
	SELECT 
		c.city AS city,
		COUNT (*) AS count_ads, --количество объявлений
		ROUND (AVG(a.days_exposition)::NUMERIC,2) AS avg_days_exposition, -- cреднее количество дней на сайте
		ROUND (COUNT (*) FILTER (WHERE a.days_exposition IS NOT NULL)::NUMERIC / COUNT (*)*100,2) AS perc_removed_ads, --доля снятых объявлений,
		ROUND(AVG (a.last_price::NUMERIC/f.total_area::NUMERIC),2) AS avg_square_meter, -- средняя стоимость кв.метра,
		ROUND(AVG (f.total_area)::NUMERIC,2) AS avg_area -- средняя площадь
	FROM real_estate.flats AS f
	LEFT JOIN real_estate.city AS c USING (city_id)
	LEFT JOIN real_estate.TYPE AS t USING (type_id)
	LEFT JOIN real_estate.advertisement AS a USING (id)
	WHERE id IN (SELECT * FROM filtered_id) AND c.city <> 'Санкт-Петербург' AND c.city = 'Кудрово'
	GROUP BY c.city
	HAVING COUNT(*) > 100
	ORDER BY count_ads DESC 
