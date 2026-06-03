-- 1. Временной интервал
-- Изучаем, за какой период представлены объявления о продаже недвижимости
SELECT 
	MIN(first_day_exposition)
	, MAX(first_day_exposition)
FROM real_estate.advertisement a
;

/*
min       |max       |
----------+----------+
2014-11-27|2019-05-03|

Данные за 2014 и 2019 годы — неполные: за 2014 год данные начинаются с конца ноября, а за 2019 — заканчиваются в мае. 
Если понадобится изучить годовую динамику параметров, выбираем только полные годы: 2015, 2016, 2017, 2018.
*/



-- 2. Типы населённых пунктов
-- Изучим распределение объявлений по населённым пунктам в зависимости от их типа
-- Подсчитаем для каждого типа количество населённых пунктов и количество объявлений

SELECT 
	t.type
	, COUNT(DISTINCT f.id) AS adv_count
	, COUNT(DISTINCT f.city_id) AS city_count
FROM real_estate.type t 
LEFT JOIN real_estate.flats f USING(type_id)
GROUP BY t.TYPE
ORDER BY adv_count DESC 
;

/*
 type                                     |adv_count|city_count|
-----------------------------------------+---------+----------+
город                                    |    20008|        43|
посёлок                                  |     2092|       113|
деревня                                  |      945|       106|
посёлок городского типа                  |      363|        30|
городской посёлок                        |      187|        13|
село                                     |       32|         9|
посёлок при железнодорожной станции      |       15|         6|
садовое товарищество                     |        4|         4|
коттеджный посёлок                       |        3|         3|
садоводческое некоммерческое товарищество|        1|         1|
 */



-- 3. Время активности объявления
-- Подсчитаем основные статистики по полю со временем активности объявлений
-- Минимальное, максимальное, среднее (округлено до двух знаков после запятой) значения и медиана

SELECT 
	MIN(days_exposition) AS min
	, MAX(days_exposition) AS max
	, ROUND(AVG(days_exposition)::numeric, 2) AS avg
	, PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY days_exposition) AS median -- медиана 
FROM real_estate.advertisement a 
;

/*
min|max   |avg   |median|
---+------+------+------+
1.0|1580.0|180.75|  95.0|

Здесь медиана отличается от среднего значения, что может говорить о наличии единичных высоких значений — выбросов. 
Результаты показывают, что половину объявлений сняли с публикации в течение 95 дней с момента публикации.
 */



-- 4. Доля снятых с публикации объявлений
-- Рассчитаем процент объявлений, которые сняли с публикации (процент проданных объектов недвижимости из опубликованных). 

WITH sold AS (
	SELECT 
		COUNT(id) AS sold_count
	FROM real_estate.advertisement a 
	WHERE days_exposition IS NOT NULL
), 
all_adv AS (
	SELECT 
		COUNT(id) AS adv_count
	FROM real_estate.advertisement a 
)
SELECT 
	ROUND(s.sold_count/a.adv_count::numeric*100, 2) AS sold_perc
FROM sold s 
CROSS JOIN all_adv a 
;

/*
sold_perc|
---------+
    86.55|
    
Около 86.55 % всех продаваемых объектов недвижимости могли быть проданы.
Процент объявлений, которые сняли с публикации, составляет 86.55. 
Если считать, что эти объекты проданы, то получается хорошая выборка данных для анализа.
 */



-- 5. Объявления Санкт-Петербурга
-- Определим процент объявлений о продаже квартир в Санкт-Петербурге.

WITH spb AS (
	SELECT 
		COUNT(f.id) AS SPB_adv
	FROM real_estate.city c 
	LEFT JOIN real_estate.flats f USING(city_id)
	WHERE c.city = 'Санкт-Петербург'
), 
total AS (
	SELECT 
		COUNT(f.id) AS total_adv
	FROM real_estate.flats f 
)
SELECT
	ROUND(s.SPB_adv/t.total_adv::NUMERIC*100, 2) AS SPB_adv_perc
FROM spb s
CROSS JOIN total t
;

/*
spb_adv_perc|
------------+
       66.47|

Соотношение между объявлениями в Санкт-Петербурге и Ленинградской области — примерно 66 к 34 или около 2 к 1. 
Такое соотношение позволяет изучить объявления в двух субъектах раздельно и сопоставить результаты между собой, 
хоть и объявлений в Санкт-Петербурге почти в два раза больше.
 */



-- 6. Стоимость квадратного метра
-- Подсчитаем основные статистические показатели для значений стоимости одного квадратного метра – минимальное, максимальное, среднее значения и медиану. 

SELECT 
	MIN(a.last_price/f.total_area) AS min
	, MAX(a.last_price/f.total_area) AS max
	, ROUND(AVG(a.last_price/f.total_area)::numeric, 2) AS avg
	, PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY a.last_price/f.total_area) AS median -- медиана 
FROM real_estate.advertisement a 
LEFT JOIN real_estate.flats f USING(id)
;

/*
min      |max      |avg     |median |
---------+---------+--------+-------+
111.83486|1907500.0|99432.25|95000.0|

Обратите внимание, что среднее значение близко к медианному, это может говорить или о том, что в данных нет выбросов или аномальных значений, 
или они есть в части как низких значений, так и высоких. 
Действительно, есть низкие значения — 112 рублей за квадратный метр, а есть и высокие — 1 907 500 рублей за квадратный метр. 
Возможно, низкие значения представлены не в рублях, а в тысячах: уж слишком они низкие. Высокие же значения вполне могут быть реальной стоимостью.
Но цель нашего анализа данных — получить общее представление о продажах недвижимости в регионах. 
Поэтому при изучении общих характеристик данных мы отфильтруем аномально высокие и низкие значения — и избежим их влияния на результат. 
Продажу недвижимости со стоимостью 1 907 500 рублей за квадратный метр как раз можно рассматривать как аномальное событие.
*/



-- 7. Статистические показатели
-- Проверим корректность данных и подсчитайте статистические показатели — минимальное и максимальное значения, среднее значение, 
-- медиану и 99 перцентиль по следующим количественным данным: общая площадь недвижимости, количество комнат и балконов, высота потолков, этаж.

-- общая площадь недвижимости
SELECT 
	MIN(total_area) AS min
	, MAX(total_area) AS max
	, ROUND(AVG(total_area)::numeric, 2) AS avg
	, PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY total_area) AS median -- медиана 
	, PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS perc99 -- 99 перцентиль 
FROM real_estate.flats f
;
/*
min |max  |avg  |median|perc99|
----+-----+-----+------+------+
12.0|900.0|60.33|  52.0| 197.9|
 */

-- кол-во комнат
SELECT 
	MIN(rooms) AS min
	, MAX(rooms) AS max
	, ROUND(AVG(rooms)::numeric, 2) AS avg
	, PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY rooms) AS median -- медиана 
	, PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS perc99 -- 99 перцентиль 
FROM real_estate.flats f
;
/*
min|max|avg |median|perc99|
---+---+----+------+------+
  0| 19|2.07|     2|     5|
 */

-- кол-во балконов
SELECT 
	MIN(balcony) AS min
	, MAX(balcony) AS max
	, ROUND(AVG(balcony)::numeric, 2) AS avg
	, PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY balcony) AS median -- медиана 
	, PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS perc99 -- 99 перцентиль 
FROM real_estate.flats f
;
/*
min|max|avg |median|perc99|
---+---+----+------+------+
0.0|5.0|1.15|   1.0|   5.0|
 */

-- высота потолков
SELECT 
	MIN(ceiling_height) AS min
	, MAX(ceiling_height) AS max
	, ROUND(AVG(ceiling_height)::numeric, 2) AS avg
	, PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY ceiling_height) AS median -- медиана 
	, PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS perc99 -- 99 перцентиль 
FROM real_estate.flats f
;
/*
min|max  |avg |median|perc99|
---+-----+----+------+------+
1.0|100.0|2.77|  2.65|  3.83|
 */

-- кол-во этажей
SELECT 
	MIN(floor) AS min
	, MAX(floor) AS max
	, ROUND(AVG(floor)::numeric, 2) AS avg
	, PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY floor) AS median -- медиана 
	, PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY floor) AS perc99 -- 99 перцентиль 
FROM real_estate.flats f
;
/*
min|max|avg |median|perc99|
---+---+----+------+------+
  1| 33|5.89|     4|    23|
 */


/*
Данные содержат аномально высокие значения практически в каждом столбце, кроме этажа недвижимости. 
Это можно проверить, если сравнить максимальное значение с 99 перцентилем. 
Столь высокие значения негативно сказываются на средних значениях, поэтому их надо будет отфильтровать при основном анализе данных.
Также смущает низкое значение высоты потолка — всего 1 метр. 
Возможно, в этом случае такое значение можно рассматривать как аномальное, и его тоже стоит отфильтровать при исследовании, например, 
проверив значение 1 перцентиля, которое будет принимать адекватные значения.
 */





