-- Анализ поведения игроков и монетизации в онлайн-игре
-- Часть 1. Исследовательский анализ данных

-- Задача 1. Исследование доли платящих игроков
-- 1.1. Доля платящих пользователей по всем данным:

SELECT
	COUNT(payer) AS total_users, -- Все игроки
	SUM (payer) AS payer_users, -- Платящие игроки
	ROUND (AVG(payer),4) AS players_share -- Доля платящих игроков от всех
FROM fantasy.users;

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:

SELECT
	r.race, -- Раса
	COUNT (u.id) AS total_users, -- Все игроки
	SUM (u.payer) AS payer_users, -- Платящие игроки
	ROUND (AVG(u.payer),4) AS share_payer_users -- Доля платящих игроков
FROM fantasy.users AS u
LEFT JOIN fantasy.race AS r 
USING (race_id)
GROUP BY r.race
ORDER BY share_payer_users;

-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:

SELECT
	COUNT (amount) AS total_orders, -- общее количество покупок
	SUM (amount::numeric) AS sum_amount, -- суммарная стоимость покупок
	MIN (amount) AS min_amount, -- минимальная стоимость
	MAX (amount) AS max_amount, -- максимальная стоимость
	ROUND (AVG (amount::numeric),2) AS avg_amount, -- средняя стоимость
	PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY amount) AS amount_mediana, -- медиана
	STDDEV (amount) AS stand_dev_amount -- стандартное отклонение
FROM fantasy.events

-- 2.2: Аномальные нулевые покупки:

SELECT
	COUNT (*) AS total_orders, -- Все покупки
	COUNT (*) FILTER (WHERE amount=0) AS null_orders, -- Нулевые покупки
	COUNT (*) FILTER (WHERE amount=0)/COUNT (*)::float AS percent_null_orders -- Доля нулевых покупок от всех
FROM fantasy.events;

-- 2.3: Сравнительный анализ активности платящих и неплатящих игроков:

WITH users_stats AS(-- Считаем данные по всем игрокам
	SELECT 
	 	u.id,
        u.payer,
        COUNT (e.transaction_id) AS total_orders, -- Всего покупок
        SUM (e.amount) AS total_amount -- Общая сумма покупок
    FROM fantasy.events AS e
    LEFT JOIN fantasy.users AS u USING (id)
    WHERE e.amount >0 -- Исключаем аномальные нулевые покупки
    GROUP BY u.id,
            u.payer -- Группируем по признаку плательщика и идентификатору игрока, т.к. игрок может совершать несколько покупок
)-- Разделяем игроков на категории
SELECT
	CASE
		WHEN payer=1 THEN 'платящий'
		WHEN payer = 0 THEN 'не платящий'
	END AS users_category,
	COUNT (id) AS count_users, 
	ROUND (AVG (total_orders),2) AS avg_orders,
	ROUND (AVG (total_amount::numeric),2) AS avg_amount
FROM users_stats
GROUP BY payer;

-- 2.4: Популярные эпические предметы:

WITH items_stats AS ( --в СТЕ считаем статистику по эпическим предметам и количеству купивших тот или иной предмет
SELECT
	i.game_items,
	COUNT (e.transaction_id) AS total_orders, -- Количество покупок
	COUNT (DISTINCT e.id) AS total_users, -- Количество игроков
	AVG (u.payer) AS share_payer_users --Доля платящих игроков
FROM fantasy.events AS e
JOIN fantasy.items AS i
USING (item_code)
JOIN fantasy.users AS u
USING (id)
WHERE e.amount >0 -- Исключаем аномальные нулевые покупки
GROUP BY i.game_items
)
SELECT
	game_items,
	total_orders,
	share_payer_users,
	ROUND ((total_orders*100.0 / (SELECT COUNT (transaction_id) FROM fantasy.events WHERE amount >0)),2) AS share_item, -- доля покупки предмета от общего числа покупок
	ROUND ((total_users*100.0 / (SELECT COUNT (DISTINCT id) FROM fantasy.events WHERE amount >0)),2) AS share_users -- доля купивших предмет от общего числа игроков
FROM items_stats
ORDER BY share_users DESC

-- Часть 2. Решение ad hoc-задач

-- Задача 1. Зависимость активности игроков от расы персонажа:

WITH all_users AS ( -- общее количество зарегистрированных игроков для каждой расы
	SELECT
		r.race, -- раса
		COUNT (u.id) AS total_users_count -- количество игроков для каждой расы
	FROM fantasy.users AS u
	LEFT JOIN fantasy.race AS r 
	USING (race_id) 
	GROUP BY r.race
),
payers_stat AS ( -- игроки, которые совершают внутриигровые покупки
SELECT 
	r.race,
	COUNT (DISTINCT u.id) AS total_payers, -- количество игроков, которые совершают внутриигровые покупки для каждой расы
	COUNT (e.transaction_id) AS total_orders, -- количесво покупок для каждой расы
	sum (e.amount) AS total_amount -- суммарная стоимость всех покупок для каждой расы
FROM fantasy.events AS e
JOIN fantasy.users AS u 
USING (id)
JOIN fantasy.race AS r 
USING (race_id)
WHERE e.amount >0
GROUP BY r.race
),
real_payers_stat AS (
SELECT 
	r.race,
	COUNT (DISTINCT u.id) AS total_real_payers -- количество платящих игроков для каждой расы
FROM fantasy.events AS e
JOIN fantasy.users AS u 
USING (id)
JOIN fantasy.race AS r 
USING (race_id)
WHERE e.amount >0 AND u.payer = 1
GROUP BY r.race
)
SELECT
	au.race, -- раса
	au.total_users_count, -- количество игроков для каждой расы
	ps.total_payers, -- количество игроков, которые совершают внутриигровые покупки для каждой расы
	rps.total_real_payers, -- количество платящих игроков для каждой расы
	ps.total_payers::real / au.total_users_count AS share_paying_users, -- доля совершивших покупку от всех игроков
	rps.total_real_payers::real / ps.total_payers AS share_real_paying_users, -- доля платящих игроков от совершивших покупку
	ps.total_orders::real/ps.total_payers AS avg_orders,-- среднее количество покупок на одного игрока
	ps.total_amount::real/ps.total_orders AS avg_amount, -- средняя стоимость одной покупки на одного игрока
	ps.total_amount::real/ps.total_payers AS avg_sum_ammount -- средняя суммарная стоимость всех покупок на одного игрока
FROM payers_stat AS ps 
JOIN all_users AS au 
USING (race) 
JOIN real_payers_stat AS rps 
USING (race);