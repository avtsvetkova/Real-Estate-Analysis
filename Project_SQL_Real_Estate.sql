/* Анализ данных для агентства недвижимости

 * Автор: Цветкова Анастасия Валерьевна
 * Дата: 10.01.2026
*/



-- Задача 1: Время активности объявлений

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдём id объявлений, которые не содержат выбросы, также оставим пропущенные данные:
filtered_id AS(
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Выделение категорий по региону и кол-ву дней до продажи, расчет ср.стоимости кв.метра:
cte AS (
	SELECT 
		CASE 
			WHEN f.city_id = '6X8I' THEN 'Санкт-Петербург'
			ELSE 'ЛенОбл'
		END AS region
		, CASE
			WHEN a.days_exposition <= 30 THEN '1-30 days'
			WHEN a.days_exposition > 30 AND a.days_exposition <= 90 THEN '31-90 days'
			WHEN a.days_exposition > 90 AND a.days_exposition <= 180 THEN '91-180 days'
			WHEN a.days_exposition > 180 THEN '> 180 days'
			ELSE 'non category'
		END AS active_category
		, ROUND(AVG(a.last_price/f.total_area)::numeric, 0) AS avg_meter_cost -- средняя стоимость одного квадратного метра недвижимости
		, ROUND(AVG(f.total_area)::numeric, 1) AS avg_area -- средняя площадь
		, PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.rooms) AS rooms_median -- медиана кол-ва комнат
		, PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.balcony) AS balcony_median -- медиана кол-ва балконов
		, PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.floor) AS floor_median -- медиана кол-ва этажей
		, ROUND(AVG(f.ceiling_height)::numeric, 1) AS avg_ceiling_height -- средняя высота потолка
		, ROUND(AVG(f.living_area)::numeric, 1) AS avg_living_area -- средняя жилая площадь
		, COUNT(f.id) AS adv_count -- кол-во объявлений по региону и категориям
		, COUNT(f.rooms) FILTER (WHERE f.rooms = 0) AS studios_count -- кол-во квартир-студий
		, COUNT(f.is_apartment) FILTER (WHERE f.is_apartment = 1) AS apart_count -- кол-во апартаментов
	FROM real_estate.flats f 
	LEFT JOIN real_estate.advertisement a USING(id)
	WHERE 
		f.id IN (SELECT * FROM filtered_id) -- id объявлений без выбросов
		AND f.type_id = 'F8EM' -- фильтр на города 
		AND a.first_day_exposition BETWEEN '2015-01-01' AND '2018-12-31'
	GROUP BY region, active_category
)
-- Основной запрос:
SELECT 
	region
	, active_category
	, adv_count -- кол-во объявлений по региону и категориям
	, ROUND(adv_count / SUM(adv_count) OVER (PARTITION BY region)::numeric * 100, 1) AS adv_cnt_per_reg_perc -- доля объявлений по регионам
	, SUM(adv_count) OVER (PARTITION BY region) AS adv_total -- кол-во объявлений по СПб и ЛО
	, avg_meter_cost -- средняя стоимость одного квадратного метра
	, avg_area -- средняя площадь
	, rooms_median -- медиана кол-ва комнат
	, balcony_median -- медиана кол-ва балконов
	, floor_median -- медиана кол-ва этажей
	, avg_ceiling_height -- средняя высота потолка
	, avg_living_area -- средняя жилая площадь
	, ROUND(studios_count / adv_count::numeric * 100, 1) AS studios_per_adv_perc -- доля студий (0 комнат) от всех объявлений
	, ROUND(apart_count / adv_count::numeric * 100, 1) AS apart_per_adv_perc -- доля апартаментов от всех объявлений
FROM cte 
ORDER BY region DESC, active_category ASC
;

/* Результат:

region         |active_category|adv_count|adv_cnt_per_reg_perc|adv_total|avg_meter_cost|avg_area|rooms_median|balcony_median|floor_median|avg_ceiling_height|avg_living_area|studios_per_adv_perc|apart_per_adv_perc|
---------------+---------------+---------+--------------------+---------+--------------+--------+------------+--------------+------------+------------------+---------------+--------------------+------------------+
Санкт-Петербург|1-30 days      |     1794|                16.0|    11217|        108920|    54.7|           2|           1.0|           5|               2.8|           30.7|                 1.6|               0.2|
Санкт-Петербург|31-90 days     |     3020|                26.9|    11217|        110874|    56.6|           2|           1.0|           5|               2.8|           31.5|                 1.2|               0.1|
Санкт-Петербург|91-180 days    |     2244|                20.0|    11217|        111974|    60.5|           2|           1.0|           5|               2.8|           33.8|                 0.6|               0.2|
Санкт-Петербург|> 180 days     |     3506|                31.3|    11217|        114981|    65.8|           2|           1.0|           5|               2.8|           37.0|                 0.5|               0.1|
Санкт-Петербург|non category   |      653|                 5.8|    11217|        136108|    81.4|           3|           1.0|           4|               2.9|           45.6|                 0.5|               1.1|
ЛенОбл         |1-30 days      |      340|                12.0|     2828|         71908|    48.8|           2|           1.0|           4|               2.7|           27.2|                 0.9|               0.6|
ЛенОбл         |31-90 days     |      864|                30.6|     2828|         67424|    50.9|           2|           1.0|           3|               2.7|           29.4|                 0.6|               0.1|
ЛенОбл         |91-180 days    |      553|                19.6|     2828|         69809|    51.8|           2|           1.0|           3|               2.7|           29.8|                 0.9|               0.0|
ЛенОбл         |> 180 days     |      873|                30.9|     2828|         68215|    55.0|           2|           1.0|           3|               2.7|           31.7|                 0.1|               0.1|
ЛенОбл         |non category   |      198|                 7.0|     2828|         72926|    62.8|           2|           1.0|           3|               2.8|           35.6|                 1.0|               0.5|
 */





-- Задача 2: Сезонность объявлений

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдём id объявлений, которые не содержат выбросы, также оставим пропущенные данные:
filtered_id AS (
    SELECT id
    FROM real_estate.flats
    WHERE
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
        AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Даты начала и конца объявлений
dates AS (
	SELECT
		a.id
		, a.first_day_exposition 
		, a.days_exposition
		, a.first_day_exposition + a.days_exposition::int AS last_day_exposition
		, EXTRACT(MONTH FROM a.first_day_exposition) AS start_month
		, EXTRACT(MONTH FROM a.first_day_exposition + a.days_exposition::int) AS end_month
	FROM real_estate.advertisement a 
	LEFT JOIN real_estate.flats f USING(id)
	WHERE 
		a.id IN (SELECT * FROM filtered_id) -- id объявлений без выбросов
		AND f.type_id = 'F8EM' -- фильтр на города 
		-- фильтр на объявления, опубликованные не раньше 2015 года и закрытые не позже 2018 года 
		-- (исключаются объявления, которые были размещены в 2014 и закрыты в 2015 или размещены в 2018 и закрыты в 2019)
		AND (a.first_day_exposition BETWEEN '2015-01-01' AND '2018-12-31'
		AND (a.first_day_exposition + a.days_exposition::int) BETWEEN '2015-01-01' AND '2018-12-31') 
), 
-- Статистика по месяцам публикации объявлений
stats_start AS (
	SELECT 
		d.start_month
		, COUNT(f.id) AS adv_count_start -- кол-во объявлений для каждого периода
		, ROUND(AVG(a.last_price / f.total_area)::numeric, 0) AS avg_meter_cost_start -- ср.стоимость квадратного метра 
		, ROUND(AVG(f.total_area)::numeric, 0) AS avg_total_area_start -- ср.площадь недвижимости
	FROM dates d 
	LEFT JOIN real_estate.advertisement a USING(id)
	LEFT JOIN real_estate.flats f USING(id)
	GROUP BY d.start_month
),
-- Статистика по месяцам снятия объявлений
stats_end AS (
	SELECT 
		d.end_month
		, COUNT(f.id) AS adv_count_end -- кол-во объявлений для каждого периода
		, ROUND(AVG(a.last_price / f.total_area)::numeric, 0) AS avg_meter_cost_end -- ср.стоимость квадратного метра 
		, ROUND(AVG(f.total_area)::numeric, 0) AS avg_total_area_end -- ср.площадь недвижимости
	FROM dates d 
	LEFT JOIN real_estate.advertisement a USING(id)
	LEFT JOIN real_estate.flats f USING(id)
	GROUP BY d.end_month
)
-- Основной запрос:
SELECT 
	s.start_month AS month
	, s.adv_count_start
	, e.adv_count_end
	, ROUND((e.adv_count_end - s.adv_count_start) / s.adv_count_start::numeric * 100, 2) AS adv_cnt_diff_perc
	, s.avg_meter_cost_start
	, e.avg_meter_cost_end
	, ROUND((e.avg_meter_cost_end - s.avg_meter_cost_start) / s.avg_meter_cost_start::numeric * 100, 2) AS avg_meter_cost_diff_perc
	, s.avg_total_area_start
	, e.avg_total_area_end
	, ROUND((e.avg_total_area_end - s.avg_total_area_start) / s.avg_total_area_start::numeric * 100, 2) AS avg_total_area_diff_perc
FROM stats_start s 
LEFT JOIN stats_end e ON s.start_month = e.end_month
ORDER BY month
;

/* Результат:

month|adv_count_start|adv_count_end|adv_cnt_diff_perc|avg_meter_cost_start|avg_meter_cost_end|avg_meter_cost_diff_perc|avg_total_area_start|avg_total_area_end|avg_total_area_diff_perc|
-----+---------------+-------------+-----------------+--------------------+------------------+------------------------+--------------------+------------------+------------------------+
    1|            674|          870|            29.08|              104266|            103815|                   -0.43|                  58|                57|                   -1.72|
    2|           1246|          740|           -40.61|              101789|            100820|                   -0.95|                  59|                60|                    1.69|
    3|           1010|          818|           -19.01|              101430|            105165|                    3.68|                  59|                58|                   -1.69|
    4|            934|          765|           -18.09|              101468|            100188|                   -1.26|                  60|                57|                   -5.00|
    5|            827|          715|           -13.54|              102255|             99559|                   -2.64|                  59|                58|                   -1.69|
    6|           1125|          771|           -31.47|              103619|            101864|                   -1.69|                  58|                60|                    3.45|
    7|            984|         1108|            12.60|              103101|            102291|                   -0.79|                  58|                59|                    1.72|
    8|            998|         1137|            13.93|              104438|            100037|                   -4.21|                  57|                57|                    0.00|
    9|           1140|         1238|             8.60|              106685|            104070|                   -2.45|                  59|                57|                   -3.39|
   10|           1113|         1360|            22.19|              101234|            104317|                    3.05|                  57|                59|                    3.51|
   11|           1181|         1301|            10.16|              102030|            103791|                    1.73|                  57|                57|                    0.00|
   12|            766|         1175|            53.39|              102061|            105505|                    3.37|                  57|                59|                    3.51|
*/
