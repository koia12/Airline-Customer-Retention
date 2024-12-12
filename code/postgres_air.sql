-- !preview conn=DBI::dbConnect(RSQLite::SQLite())

#the following queries explore the postgres_air 
#database. This Entity-Relationship diagram shows
#how the tables relate to each other:


#look at some of the relations between flight
#and aircraft. We know airlines select larger
#planes with greater range for longer flights:

#see which aircraft are used the most:
SELECT aircraft_code, count(*) from postgres_air.flight
GROUP BY 1;

#see which flight numbers use multiple types
#of aircraft:
SELECT flight_no, count(distinct(aircraft_code)) from postgres_air.flight
GROUP BY 1
ORDER BY 2 desc
;

#how many distinct routes (from different carriers)
#for each pair of departure_airport and arrival_airport:
SELECT arrival_airport, departure_airport, 
count(distinct(flight_no))
from postgres_air.flight
GROUP BY 1,2
ORDER BY 3 desc
;

#look at histogram for these:

SELECT departure_airport, arrival_airport, 
count(distinct(flight_no)) as n_flights_per_route,
concat(departure_airport,'-',arrival_airport) as route
from postgres_air.flight
GROUP BY 1,2
;

#few routes have more than 1 distinct flight_no:
SELECT a.n_flights_per_route, count(*)
FROM
(
  SELECT departure_airport, arrival_airport, 
  count(distinct(flight_no)) as n_flights_per_route,
  concat(departure_airport,'-',arrival_airport) as route
  from postgres_air.flight
  GROUP BY 1,2
) a
GROUP BY 1
;


#look for trend in aircraft use given range.
#We should expect aircraft with less range
#to be used far more, since most of the
#aircraft in commercial use are in the A320
#or B737 family, smaller airplanes with 
#shorter range:https://www.flightaware.com/live/aircrafttype/

SELECT a.aircraft_code, b.range, b.class, count(*)
FROM
(
  SELECT * from postgres_air.flight
)a
LEFT JOIN
(
  SELECT * from postgres_air.aircraft
)b
on a.aircraft_code = b.code
GROUP BY 1,2,3
ORDER BY 4 desc
;

#interestingly some aircraft that are in 
#much lower use today like the CRJ2 and 
#Boeing 767 rank highly; possily because
#this is historical or simulated data


#now explore trend between route and model

SELECT concat(a.departure_airport, '-', a.arrival_airport) as route,
b.model, b.range,count(flight_id)
FROM
(
  SELECT departure_airport, arrival_airport, aircraft_code
  from postgres_air.flight
)a
LEFT JOIN
(
  SELECT code, model, range from postgres_air.aircraft
)b
on a.aircraft_code = b.code
GROUP BY 1,2,3
;


#see biggest differences in aircraft range over a given route:
SELECT a.route, b.model, b.range, min(b.range) over (partition by route) as min,
max(b.range) over (partition by route) as max,
max(b.range) over (partition by route) - min(b.range) over (partition by route) as diff
FROM
(
  SELECT departure_airport, arrival_airport, aircraft_code,
	concat(departure_airport, '-', arrival_airport) as route
  from postgres_air.flight
)a
LEFT JOIN
(
  SELECT code, model, range from postgres_air.aircraft
)b
on a.aircraft_code = b.code
GROUP BY 1,2,3
ORDER BY 6 desc
;

#some large gaps in range occur due to the high range
#of the A330; let's see if these routes are regularly
#flown by planes with such different ranges, or rarely:

SELECT a.route, a.flight_count, a.aircraft_code,
b.range, max(flight_count) over (partition by route) as max_flight,
min(flight_count) over (partition by route) as min_flight,
max(range) over (partition by route) - min(range) over (partition by route) as diff
FROM
(
	SELECT concat(departure_airport,'-',arrival_airport) as route, aircraft_code,
	count(flight_no) as flight_count
	from postgres_air.flight
	GROUP BY 1,2
)a
LEFT JOIN
(
	SELECT * from postgres_air.aircraft
)b
on a.aircraft_code = b.code
WHERE flight_count NOT IN (78,182)
ORDER BY 7 desc, 1
;

#using stacked bar chart makes clear that on only a handful
#of routes are two planes regularly flown: MaxMinFlights.png


SELECT a.route, a.flight_count, a.aircraft_code,
b.range, max(range) over (partition by route) as max,
min(range) over (partition by route) as min,
max(range) over (partition by route) - min(range) over (partition by route) as diff
FROM
(
	SELECT concat(departure_airport,'-',arrival_airport) as route, aircraft_code,
	count(flight_no) as flight_count
	from postgres_air.flight
	GROUP BY 1,2
)a
LEFT JOIN
(
	SELECT * from postgres_air.aircraft
)b
on a.aircraft_code = b.code
WHERE flight_count NOT IN (78,182)
GROUP BY 1,2,3,4
ORDER BY 7 desc, 1

#Database doesn't contain information about exact geographic coordinates or way
#to find distance between airport. We can look at relation between range, velocity,
#and flight time to guess:

#SELECT date_subtract(a.actual_arrival, a.actual_departure)
#SELECT a.actual_arrival - a.actual_departure,

SELECT * from 
(
	SELECT * from postgres_air.flight
) a
LEFT JOIN
(
 SELECT airport_code as dep_code, city as dep_city, airport_tz as dep_tz
	from postgres_air.airport
) b on a.departure_airport = b.dep_code
LEFT JOIN
(
	 SELECT airport_code as arr_code, city as arr_city, airport_tz as arr_tz
	from postgres_air.airport
) c on a.arrival_airport = c.arr_code

;

#look at distribution of flight times; it looks like many negative flight times.

SELECT distinct(a.nt), min(a.flight_length) over (partition by a.nt) as min, 
max(a.flight_length) over (partition by a.nt) as max
FROM
(
	SELECT actual_arrival, actual_departure, departure_airport, arrival_airport, 
	actual_arrival - actual_departure as flight_length, 
	ntile(50) over (order by actual_arrival - actual_departure) as nt
	FROM postgres_air.flight
	WHERE actual_arrival IS NOT NULL
) a	
ORDER by nt 
;

#Most immediate possibility is arrival and departure times were confused.
#check for outlier routes with issues; no obvious pattern:
SELECT route, count(*)
FROM
(
	SELECT concat(departure_airport,'-',arrival_airport) as route, 
	extract(epoch from (actual_arrival - actual_departure))/60 as act,
	extract(epoch from (scheduled_arrival - scheduled_departure))/60 as sched
	from postgres_air.flight
	WHERE actual_arrival IS NOT NULL
	AND extract(epoch from (actual_arrival - actual_departure)) < 0
) a	
GROUP BY 1
ORDER BY 2 desc
;

#Create histogram of arrival delays, heavily concentrated at exactly 0 minutes,
#suggesting measurements are imprecise and if the flight was roughly on time, it
#was given the exact scheduled arrival time as its actual arrival time.
SELECT arrival_delay_minutes, count(*) FROM
(SELECT flight_id, scheduled_departure::date, scheduled_arrival,
departure_airport, arrival_airport, actual_departure, actual_arrival, 
round(extract(epoch from (actual_arrival - scheduled_arrival))/60,0) as arrival_delay_minutes  
FROM postgres_air.flight
WHERE actual_arrival IS NOT NULL)a
GROUP BY a.arrival_delay_minutes
ORDER BY a.arrival_delay_minutes


#Notable that all of these flights were cancelled or delayed, compared to 
#about 15% of all flights cancelled or delayed:
SELECT status, count(*)
FROM
(
	SELECT * from postgres_air.flight
	WHERE actual_departure IS NOT NULL
	AND extract(epoch from actual_arrival - actual_departure)<0
) b
GROUP BY 1
;

#investigate trend in departure for flights with negative duration.
#Perusing this table, two patterns appear: either a very small difference
#between actual arrival and scheduled arrival despite a flight being severely
#delayed (suggesting the actual arrival times may be filled in from other flights
#or otherwise inaccurate) and fights where the difference between actual arrival
#and scheduled arrival is the exact negative of the difference between actual
#departure and scheduled departure, strongly suggesting the arrival and departure time
#was flipped for these flights:

SELECT extract(epoch from actual_arrival - scheduled_arrival)/60 as arriv_diff_minutes,
extract(epoch from actual_departure - scheduled_departure)/60 as depart_diff_minutes
FROM postgres_air.flight
WHERE actual_departure IS NOT NULL
AND extract(epoch from actual_arrival - actual_departure)<0
;

SELECT actual_arrival, scheduled_arrival, actual_departure, scheduled_departure,
extract(epoch from actual_arrival - scheduled_arrival)/60 as arr,
extract(epoch from actual_departure - scheduled_departure)/60 as dep
from postgres_air.flight
WHERE extract(epoch from actual_arrival - scheduled_arrival)/60 = 
-(extract(epoch from actual_departure - scheduled_departure)/60) 
;

#we now look at differences between flights with time over 0 minutes and flights
#under 0 minutes; how many records have negative flight length. Some routes have 
#a very high proportion of flights with negative flight length, and most have some
#positive flight lengths that are still impossibly short (lasting a few minutes on
#a flight that is supposed to take hours):

SELECT aa.route, aa.schedule_length, aa.count_flight_mins_under_0, aa.min_length_under_0, 
aa.max_length_under_0, bb.count_flight_mins_over_0, bb.min_length_over_0, bb.max_length_over_0,
aa.count_flight_mins_under_0 / (aa.count_flight_mins_under_0 + bb.count_flight_mins_over_0 )::float as proportion_error 
FROM
(
	SELECT a.route, a.min_length_under_0, a.max_length_under_0, a.schedule_length,
	count(*) as count_flight_mins_under_0
	FROM
	(
		SELECT concat(departure_airport, '-', arrival_airport) as route,
		extract(epoch from (scheduled_arrival - scheduled_departure))/60 as schedule_length,
		extract(epoch from (actual_arrival - actual_departure))/60 as flight_mins,
		max(extract(epoch from (actual_arrival - actual_departure))/60) over (partition by concat(departure_airport, '-', arrival_airport)) as max_length_under_0,
		min(extract(epoch from (actual_arrival - actual_departure))/60) over (partition by concat(departure_airport, '-', arrival_airport)) as min_length_under_0
		from postgres_air.flight
		WHERE actual_arrival IS NOT NULL
		AND extract(epoch from (actual_arrival - actual_departure))<0
	)a
	GROUP BY 1,2,3,4
	) aa
LEFT JOIN 
	(
	SELECT b.route, b.max_length_over_0, b.min_length_over_0,
	count(*) as count_flight_mins_over_0
	FROM
	(
		SELECT concat(departure_airport, '-', arrival_airport) as route, 
		extract(epoch from (actual_arrival - actual_departure))/60 as flight_mins,
		max(extract(epoch from (actual_arrival - actual_departure))/60) over (partition by concat(departure_airport, '-', arrival_airport)) as max_length_over_0,
		min(extract(epoch from (actual_arrival - actual_departure))/60) over (partition by concat(departure_airport, '-', arrival_airport)) as min_length_over_0
		from postgres_air.flight
		WHERE actual_arrival IS NOT NULL
		AND extract(epoch from (actual_arrival - actual_departure))>=0
	) b
	WHERE b.flight_mins >= 0
	GROUP BY 1,2,3
)bb
ON aa.route = bb.route
ORDER BY 9 desc

#a typical record of a route reveals a multimodal distribution of flight lengths where
#we would expect something approaching normality:
SELECT concat(departure_airport, '-', arrival_airport) as route,
extract(epoch from (scheduled_arrival - scheduled_departure))/60 as scheduled_length,
extract(epoch from (actual_arrival - actual_departure))/60 as flight_length
from postgres_air.flight
WHERE actual_departure IS NOT NULL
AND concat(departure_airport, '-', arrival_airport) = 'ATL-CLT'
;
#R code:
ATLCLT <- read_csv("C:/Users/fhold/Downloads/postgres_air_2023.sql/ATLCLT.csv")
hist(ATLCLT$flight_length, breaks = 40)

#Insert altclt.png here

#First of all, roughly a third of the records have flight length of exactly 55.000
#minutes, the scheduled_length, when the timestamp is accurate to the second mark
#and we would expect far less precision, suggesting the actual_arrival or actual_departure
#time was fudged and just set as the other actually recorder time plus the scheduled length.
#We also see another mode of impossibly short flight times at 25-30 minutes, as well as a long
#shoulder of negative flight times, concentrating near the negative of the scheduled length 
#of the flight.

#making a histogram of ratio of length of flight to the scheduled length of flight for
#all flights reveals the same pattern, but smooother given a far larger list of data: 
#extreme peak at the exact scheduled flight length, larger left shoulder than right shoulder,
#slight second mode at a ratio of around -0.1, and many impossibly short positive flight times:

SELECT (a.flight_length - a.scheduled_length)/a.scheduled_length as ratio_length
FROM
(
	SELECT concat(departure_airport, '-', arrival_airport) as route,
	extract(epoch from (scheduled_arrival - scheduled_departure))/60 as scheduled_length,
	extract(epoch from (actual_arrival - actual_departure))/60 as flight_length
	from postgres_air.flight
	WHERE actual_departure IS NOT NULL
)a

#R code:
all_flights_ratio <- read_csv("C:/Users/fhold/Downloads/postgres_air_2023.sql/all_flights_ratio.csv")
hist(all_flights_ratio$ratio_length, breaks = 500)

#insert all_flights_ratio.png

#I suspect the left shoulder should more closely resemble the right one. It's possible that
#there should be some asymmetry as the scheduled flight length may be a conservative estimate
#based on a worst case scenario of time spent from cabin doors closing to takeoff or other factors.
#For example, the aerial distance from Atlanta to Charlotte is 227 miles and the scheduled flight
#time is 55 minutes on a plane whose max velocity is 630 miles per hour. While this doesn't mean
#the entire flight could be achieved in 20 minutes, it does suggest that this ratio may not converge
#to a normal distribution, if the scheduled time is a worst case scenario. If our analysis depended
#more on fixing these, we could look up the GPS coordinates of all airports (not included in database)
#and calculate minimum aerial distance between two airports, and cut off all flight times that are less
#than the aerial distance divided by the maximum velocity of the aircraft.

#For now, we move on to exploring other aspects of the database. We may want to inspect
#the booking habits of frequent flyer customers:

SELECT * from
(
	(SELECT account_id, upper(first_name) as first_name, 
	upper(last_name) as last_name, frequent_flyer_id 
	from postgres_air.account) a
	INNER JOIN
	(SELECT level, award_points, frequent_flyer_id 
	from postgres_air.frequent_flyer)b
	ON a.frequent_flyer_id = b.frequent_flyer_id 	
)

#Seems some accounts are used by several different passengers:
SELECT account_id, concat(upper(first_name), '.', upper(last_name)) as name, count(*)
from postgres_air.passenger
GROUP BY 1,2

#Which accounts were used for the most flights:
SELECT account_id, count(a.name)
FROM
(
	SELECT account_id, concat(upper(first_name), '.', upper(last_name)) as name
	from postgres_air.passenger
	WHERE account_id IS NOT NULL
)a
GROUP BY 1
ORDER BY 2 desc

#Which accounts were used by the most passengers (with distinct names):
SELECT account_id, count (distinct a.name)
FROM
(
	SELECT account_id, concat(upper(first_name), '.', upper(last_name)) as name
	from postgres_air.passenger
	WHERE account_id IS NOT NULL
)a
GROUP BY 1
ORDER BY 2 desc

#some of these are used by hundreds or thousands of people, suggesting they may
#be a company account. However, the most common passenger on most accounts has
#the same name as the account holder often. We pull the
#passenger name with the most flights on each account from the passenger table 
#and join to the account table:

SELECT * from
(SELECT * from
(
	(SELECT account_id, concat(upper(first_name),'.', upper(last_name)) as name,
	frequent_flyer_id from postgres_air.account) a
	INNER JOIN
	(SELECT level, award_points, frequent_flyer_id 
	from postgres_air.frequent_flyer)b
	ON a.frequent_flyer_id = b.frequent_flyer_id 	
))aa
INNER JOIN
(SELECT * from
(SELECT account_id, name, count, max(count) over (partition by account_id) as max_count
FROM
(
	SELECT account_id, concat(upper(first_name),'.',upper(last_name)) as name, count(*)
	from postgres_air.passenger
	GROUP BY 1,2
)a
)b WHERE max_count = count
)bb on aa.account_id = bb.account_id

#This returns 87141 records compared to 128000 from the account table.
#This suggests about a third of account IDs in account table do not have a record in 
#passenger table, even though some of the same accounts do have a record in the 
#booking table. If we do the same previous query but also join on aa.name = bb.name,
#we get 87043 records, so the customer on the account name is almost always the most
#common customer to fly.

#bookings often have more than one passenger, but the max is only 5:
SELECT count, count(count) as total
FROM
(
	SELECT booking_id, count(passenger_id) 
	from postgres_air.passenger
	GROUP BY 1
	ORDER BY 2 desc
)a
GROUP BY 1

#the number of booking ids varies for the same account
#between passenger and booking tables, with no immediately
#obvious pattern (like more than one passenger per booking)

SELECT * from
(SELECT account_id, count(distinct booking_id) as book_count
FROM postgres_air.booking 
GROUP BY 1) a
JOIN
(SELECT account_id, count(distinct booking_id) as pass_count
FROM postgres_air.passenger
GROUP BY 1) b
ON a.account_id = b.account_id

#look at relationship between boarding_pass table and 
#passenger table:
SELECT * from
(SELECT passenger_id, booking_id, first_name, last_name, account_id
from postgres_air.passenger
WHERE booking_id IS NOT NULL)a
LEFT JOIN
(SELECT pass_id, passenger_id, booking_leg_id 
from postgres_air.boarding_pass)b
ON a.passenger_id = b.passenger_id


#Passenger and booking_leg tables;

SELECT * from
(
	SELECT passenger_id, booking_id
	from postgres_air.passenger
)a
LEFT JOIN
(
	SELECT booking_id, flight_id
	from postgres_air.booking_leg
)b
on a.booking_id = b.booking_id

#there is an issue with the passenger_id
#key between passenger table and boarding_pass
#table. We can see this by simply comparing the
#count of distinct passenger_ids in each:

SELECT count(distinct passenger_id) from
postgres_air.passenger
;

SELECT count(distinct passenger_id) from
postgres_air.boarding_pass
;

#many passenger_ids from passenger are not
#in boarding_pass but none in reverse:
SELECT * from
(SELECT distinct passenger_id from postgres_air.passenger) a
LEFT JOIN
(SELECT distinct passenger_id from postgres_air.boarding_pass) b
on a.passenger_id = b.passenger_id
WHERE b.passenger_id IS NULL
;


SELECT * from
(SELECT a.passenger_id from
(SELECT distinct passenger_id from postgres_air.passenger
WHERE passenger_id > 8000000) a
LEFT JOIN
(SELECT distinct passenger_id from postgres_air.boarding_pass
where passenger_id > 8000000) b
on a.passenger_id = b.passenger_id
WHERE b.passenger_id IS NULL
LIMIT 1000
)aa
LEFT JOIN
(SELECT * from postgres_air.passenger)bb
on aa.passenger_id = bb.passenger_id
ORDER BY booking_id
;

#Any way we approach the boarding_pass table
#roughly half the rows are missing if we try
#to join with other tables in the database







#three way join with passenger, booking_leg,
#and boarding_pass to investigate, since each
#has a one-to-one key with booking_leg
SELECT * from
(
(SELECT * from postgres_air.boarding_pass
ORDER BY booking_leg_id
LIMIT 1000)a
LEFT JOIN
(SELECT * from postgres_air.booking_leg
WHERE booking_leg_id <=294) b
on a.booking_leg_id = b.booking_leg_id
LEFT JOIN
(SELECT * from postgres_air.passenger
WHERE booking_id <= 304847) c
on b.booking_id = c.booking_id)
;


#Boarding_pass and booking_leg:
SELECT * from
(
SELECT pass_id, passenger_id, booking_leg_id
from postgres_air.boarding_pass
)a 
LEFT JOIN
(
SELECT booking_leg_id, booking_id, flight_id
from postgres_air.booking_leg) b
on a.booking_leg_id = b.booking_leg_id


SELECT * from
(SELECT distinct passenger_id from postgres_air.passenger) a
LEFT JOIN
(SELECT distinct passenger_id from postgres_air.boarding_pass) b
on a.passenger_id = b.passenger_id
WHERE b.passenger_id IS NULL

#three way join between passenger, booking_leg, and boarding_pass.
SELECT * from
(SELECT * from
(SELECT update_ts, account_id, first_name, last_name,
booking_id, passenger_id from postgres_air.passenger
WHERE account_id % 100 = 51) a
LEFT JOIN
(SELECT booking_id, flight_id, leg_num, booking_leg_id,
update_ts from postgres_air.booking_leg)b
on a.booking_id = b.booking_id) aa
LEFT JOIN
(SELECT boarding_time, booking_leg_id, passenger_id,
pass_id, update_ts from postgres_air.boarding_pass)c
on aa.booking_leg_id = c.booking_leg_id

#where c.booking_leg_id IS NULL 84,000 rows
#where c.booking_leg_id IS NOT NULL 235,000 rows
#same result and number on NULLs if we join instead
#on aa.passenger_id = c.passenger_id. Possible that this results because
#passengers missed these flights and took another. But this query makes
#clear that a passenger name either has all their flights in the boarding
#table or none of them:

SELECT * from
(SELECT * from
(SELECT update_ts, account_id, first_name, last_name,
booking_id, passenger_id from postgres_air.passenger
WHERE account_id % 100 = 51) a
LEFT JOIN
(SELECT booking_id, flight_id, leg_num, booking_leg_id,
update_ts from postgres_air.booking_leg)b
on a.booking_id = b.booking_id) aa
LEFT JOIN
(SELECT boarding_time, booking_leg_id, passenger_id,
pass_id, update_ts from postgres_air.boarding_pass)c
on aa.passenger_id = c.passenger_id
WHERE account_id = 143051 
ORDER BY first_name,last_name

#Though further joining this with the flight table reveals
#that the missing values from boarding table coincide with flights
#that are missing their actual arrival and departure times:

SELECT * from
(SELECT * from
(SELECT update_ts, account_id, first_name, last_name,
booking_id, passenger_id from postgres_air.passenger
WHERE account_id % 100 = 51) a
LEFT JOIN
(SELECT booking_id, flight_id, leg_num, booking_leg_id,
update_ts from postgres_air.booking_leg)b
on a.booking_id = b.booking_id) aa
LEFT JOIN
(SELECT boarding_time, booking_leg_id, passenger_id,
pass_id, update_ts from postgres_air.boarding_pass)c
on aa.passenger_id = c.passenger_id
LEFT JOIN postgres_air.flight d on aa.flight_id = d.flight_id
WHERE account_id = 143051 
ORDER by first_name, last_name

#Though joining to the flight table reveals that these missing flights
#are simply future trips that have not yet taken place, but for which
#we already have passengers making bookings:

SELECT * from
(SELECT * from
(SELECT update_ts, account_id, first_name, last_name,
booking_id, passenger_id from postgres_air.passenger
WHERE account_id % 100 = 51) a
LEFT JOIN
(SELECT booking_id, flight_id, leg_num, booking_leg_id,
update_ts from postgres_air.booking_leg)b
on a.booking_id = b.booking_id) aa
LEFT JOIN
(SELECT boarding_time, booking_leg_id, passenger_id,
pass_id, update_ts from postgres_air.boarding_pass)c
on aa.passenger_id = c.passenger_id
LEFT JOIN postgres_air.flight d on aa.flight_id = d.flight_id
ORDER BY d.flight_no, scheduled_departure

#update_ts from booking_leg is the time they made the booking.
#(same boarding time as booking table as evidence by running this
#query with and without where clause:
SELECT * from
(SELECT * from postgres_air.booking 
WHERE account_id % 1000 = 51)a
LEFT JOIN
(SELECT * from postgres_air.booking_leg)b
on a.booking_id = b.booking_id
WHERE a.update_ts = b.update_ts
;)

#distribution of how early flights were booked:
SELECT actual_departure, booking_time, round(extract(epoch from actual_departure - booking_time)/(60*60*24), 0) as early_days from
(SELECT booking_id, flight_id, update_ts as booking_time from postgres_air.booking_leg
)a
LEFT JOIN
(SELECT * from postgres_air.flight)b
on a.flight_id = b.flight_id
WHERE actual_departure IS NOT NULL
ORDER BY early_days 
;

COPY(
SELECT actual_departure, booking_time, round(extract(epoch from actual_departure - booking_time)/(60*60*24), 0) as early_days from
(SELECT booking_id, flight_id, update_ts as booking_time from postgres_air.booking_leg
)a
LEFT JOIN
(SELECT * from postgres_air.flight)b
on a.flight_id = b.flight_id
WHERE actual_departure IS NOT NULL
ORDER BY early_days) to 'C:/Users/fhold/Downloads/earlybooking.csv' DELIMITER ',' CSV HEADER;

hist(earlybooking$early_days[earlybooking$early_days>0], breaks = 30, main = "Time from Booking to Flight")
#post timefrombooking.png

#this multimodal distribution of flight times peaks at both around 77 and again at 88.
#look for a trend in whether certain accounts fall into one part of the distribution
#or the other but it appears all accounts fall into the valley between the modes
#at between 82 and 84 days before flight with sufficiently high number of bookings:

SELECT * from
(SELECT account_id, avg(early_days), max(early_days), min(early_days), count(*) from
(SELECT booking_id, actual_departure, booking_time, round(extract(epoch from actual_departure - booking_time)/(60*60*24), 0) as early_days from
(SELECT booking_id, flight_id, update_ts as booking_time from postgres_air.booking_leg
)a
LEFT JOIN
(SELECT * from postgres_air.flight)b
on a.flight_id = b.flight_id
WHERE actual_departure IS NOT NULL 
AND extract(epoch from actual_departure - booking_time) > 0)aa
INNER JOIN postgres_air.passenger c on aa.booking_id = c.booking_id
GROUP BY 1)bb
WHERE count>100 
ORDER BY avg desc
;

#look at general times when bookings were made in passenger table
SELECT update_ts, count(*) from
(SELECT update_ts::date from postgres_air.booking)a
GROUP BY 1
ORDER BY 1

#visualizing this with barchart makes clear that there is a gap of nearly a month
#from mid May to mid June where dramatically fewer if any bookings were made. 
#This must be an issue in our data collection, since there's no reason for zero
#bookings to be made for several weeks when tens of thousands of records exist
#for other days.

#insert BookingDateBarChart.png

#we return to our previous query to see if trend in premature booking time
#tracks with this split in the data:
SELECT * from
(SELECT early_days_before_june, count(*) as before_june_count from
(SELECT scheduled_departure, booking_time, 
 case when booking_time < '2023-05-15'::date then early_days 
		   else NULL end as early_days_before_June,
 case when booking_time >= '2023-05-15'::date then
		   early_days 
		   else NULL end as early_days_after_May
FROM
(SELECT scheduled_departure, booking_time, 
round(extract(epoch from scheduled_departure - booking_time)/(60*60*24), 0) as early_days
FROM
(SELECT booking_id, flight_id, update_ts::date as booking_time from postgres_air.booking_leg
)a
LEFT JOIN
(SELECT * from postgres_air.flight)b
on a.flight_id = b.flight_id
AND extract(epoch from scheduled_departure - booking_time) > 0) aa
)bb
GROUP BY 1)aaa
LEFT JOIN
(SELECT early_days_after_may, count(*) as after_may_count from
(SELECT scheduled_departure, booking_time, 
 case when booking_time < '2023-05-15'::date then early_days 
		   else NULL end as early_days_before_June,
 case when booking_time >= '2023-05-15'::date then
		   early_days 
		   else NULL end as early_days_after_May
FROM
(SELECT scheduled_departure, booking_time, 
round(extract(epoch from scheduled_departure - booking_time)/(60*60*24), 0) as early_days
FROM
(SELECT booking_id, flight_id, update_ts::date as booking_time from postgres_air.booking_leg
)a
LEFT JOIN
(SELECT * from postgres_air.flight)b
on a.flight_id = b.flight_id
AND extract(epoch from scheduled_departure - booking_time) > 0) aa
)bb
GROUP BY 1)bbb
on aaa.early_days_before_june = bbb.early_days_after_may
ORDER by early_days_before_june
 
#There doesn't appear to be any trend from one side of the split to the other
#Insert comparison image

#we might be interested in how, say, a delayed flight impacts the willingness of
#a customer to make another booking.

#This query joining booking_leg and flight tables shows which bookings 
#had a flight leg land after their next flight had already taken off
#(negative value of mins_since_last_flight_arrival), and flags the bookings
#where a flight was missed 

SELECT booking_id, flight_id, leg_num, actual_departure, actual_arrival, mins_since_last_flight_arrival,
case when min(mins_since_last_flight_arrival) over(partition by booking_id) < 5 THEN 'Missed_flight' 
ELSE 'Made_flight' END as Missed_flight_flag
FROM
(SELECT booking_id, a.flight_id, leg_num, is_returning, actual_departure, actual_arrival,
departure_airport, scheduled_departure, scheduled_arrival, 
round(extract(epoch from (actual_departure - lag(actual_arrival) over(partition by booking_id ORDER BY  leg_num)))/60,0)
as mins_since_last_flight_arrival
FROM
(SELECT * FROM postgres_air.booking_leg
)a
LEFT JOIN
(SELECT actual_departure, actual_arrival, departure_airport, 
scheduled_departure, scheduled_arrival, flight_id FROM postgres_air.flight)b
on a.flight_id = b.flight_id
ORDER BY booking_id, leg_num
)c

#join all delayed flights from flight table with booking leg table to see all customers who had a flight delayed
SELECT * FROM
(SELECT * FROM
(SELECT * FROM 
(SELECT flight_id, scheduled_departure::date, scheduled_arrival,
departure_airport, arrival_airport, actual_departure, actual_arrival, 
round(extract(epoch from (actual_arrival - scheduled_arrival))/60,0) as arrival_delay_minutes  
FROM postgres_air.flight
WHERE actual_arrival IS NOT NULL
AND extract(epoch from (actual_arrival - scheduled_arrival)) > 0
LIMIT 1000)a
LEFT JOIN 
(SELECT booking_id, flight_id as flght_id
FROM postgres_air.booking_leg)b
on a.flight_id = b.flght_id)aa
LEFT JOIN 
(SELECT passenger_id, booking_id as book_id, account_id
FROM postgres_air.passenger)c
on aa.booking_id = c.book_id)bb
LEFT JOIN
(SELECT booking_id, account_id, update_ts
FROM postgres_air.booking)d
ON bb.book_id = d.booking_id
WHERE update_ts IS NOT NULL
ORDER BY update_ts desc

#This long query also creates cumulative bookings on an account,
#cumulative missed flights, time from opening of the data set window
#to the booking time, and time from booking time to closing of the data
#set window so we can see how many flights we booked before and after
#a flight was missed, as well as rates of flights booked per day on 
#an account:

SELECT account_id, booking_id, updat_ts, cumulative_bookings, actual_departure, actual_arrival, 
remaining_bookings, Missed_flight_flag,scheduled_departure, scheduled_arrival, max_rn, 
mins_since_last_flight_arrival,min_flight_time, max_flight_time, days_since_start_of_dataset, days_to_end_of_dataset, row_number,
cumulative_missed_flights_by_account, days_since_first_flight, days_to_last_flight, 
cumulative_bookings / GREATEST (1, days_since_start_of_dataset)as booking_rate_so_far,
cumulative_bookings / GREATEST (1, days_since_first_flight) as booking_rate_since_first_flight, 
remaining_bookings / GREATEST(1, days_to_end_of_dataset) as rate_remaining,
remaining_bookings / GREATEST(1, days_to_last_flight) as rate_to_last_flight
FROM
(SELECT account_id, booking_id, updat_ts, cumulative_bookings, actual_departure, actual_arrival, 
remaining_bookings, Missed_flight_flag,scheduled_departure, scheduled_arrival, max_rn, 
mins_since_last_flight_arrival,min_flight_time, max_flight_time, 
round(extract(epoch from (updat_ts - min(updat_ts) over (order by updat_ts)))/(24*60*60))
 as days_since_start_of_dataset, round(extract(epoch from (scheduled_departure - min_flight_time))/(24*60*60))
 as days_since_first_flight, round(extract(epoch from (max_flight_time - scheduled_departure))/(24*60*60)) 
 as days_to_last_flight,round(extract(epoch from (max(updat_ts) over (order by updat_ts RANGE BETWEEN UNBOUNDED
													  PRECEDING AND UNBOUNDED FOLLOWING) - updat_ts))/(24*60*60))
as days_to_end_of_dataset, row_number, sum(Missed_flight_flag)
over (partition by account_id order by updat_ts) as cumulative_missed_flights_by_account,
count(actual_arrival) over
 (partition by account_id order by actual_arrival) as cum_arrival_count FROM
(SELECT account_id, booking_id, updat_ts, cumulative_bookings, actual_departure, actual_arrival, 
 scheduled_departure, scheduled_arrival, case when min(mins_since_last_flight_arrival) over(partition by booking_id) < 5 THEN 1 
, mins_since_last_flight_arrival, min_flight_time, max_flight_time, row_number, max(row_number) over (partition by booking_id)
 as max_rn, max(cumulative_bookings) over (partition by account_id) - cumulative_bookings as remaining_bookings FROM
(SELECT account_id, updat_ts, cumulative_bookings, scheduled_departure, scheduled_arrival, booking_id,
flight_id, actual_departure, actual_arrival, round(extract(epoch from(actual_departure - lag(actual_arrival)
																over(partition by booking_id ORDER BY  leg_num)))/60, 0)
as mins_since_last_flight_arrival, row_number() over (partition by booking_id order by updat_ts), 
 min(scheduled_departure) over (order by scheduled_departure) as min_flight_time, max(scheduled_departure) over 
 (order by scheduled_departure RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as max_flight_time
FROM
((SELECT booking_id as book_id, account_id, update_ts as updat_ts, 
count(booking_id) over (partition by account_id order by update_ts) as cumulative_bookings
FROM postgres_air.booking
ORDER BY account_id
)a
LEFT JOIN
(SELECT booking_id, flight_id as flght_id, booking_leg_id,leg_num FROM postgres_air.booking_leg)b
on a.book_id = b.booking_id
)aa
LEFT JOIN
(SELECT * FROM postgres_air.flight)c
on aa.flght_id = c.flight_id
ORDER BY account_id, updat_ts
)bb
)cc
WHERE row_number = max_rn
and Missed_flight_flag = 1
)dd

#as there are only 175 flights in the data set with any passengers 
#having missed their connecting flight, or with their next flight
#less than 5 minutes after arrival, the sample of passengers who
#missed a connection is small.


#Simply turning the previous query into a subquery and some basic 
#summations shows that accounts had bookings at a significantly
#lower rate over the rest of the dataset after missing a flight 
#(.05 flights per day after vs .08 trips per day before missing a flight).
#This is still an unreliable result with such a small sample of missed flights,
#and with such a short window of time (around two months of bookings and five
#months of flights), it is highly dependent on when flights were missed within
#this window of time, and a given account's or passenger's true average booking
#rate is unlikely to stabilize without years of data.
#The average rate for all accounts that didn't miss a flight is .04 flights
#per day, so the missed flights happened disproportionately to high volume
#accounts, and these accounts still booked more flights per day after missing
#than the average account.
#However, the same code could be repeated with a larger dataset.


SELECT ee.account_id, ee.updat_ts, vv.actual_arrival_filled, ee.count_2, vv.rn, ee.mins_since_last_flight_arrival,
extract(epoch from (ee.updat_ts - vv.actual_arrival_filled))/3600 as hours_to_next_booking FROM
(SELECT account_id, booking_id, updat_ts, actual_arrival_filled, count(actual_arrival_filled > updat_ts) over (partition by account_id),
sum(case when (updat_ts > actual_arrival_filled) then 1 else 0 end) over (partition by account_id order by updat_ts)+1 as count_2,
row_number() over(partition by account_id order by actual_arrival_filled) as rn, cumulative_bookings, actual_departure,
actual_arrival, remaining_bookings, Missed_flight_flag,scheduled_departure, scheduled_arrival, max_rn, 
mins_since_last_flight_arrival,min_flight_time, max_flight_time, days_since_start_of_dataset, days_to_end_of_dataset, row_number,
cumulative_missed_flights_by_account, days_since_first_flight, days_to_last_flight, 
cumulative_bookings / GREATEST (1, days_since_start_of_dataset)as booking_rate_so_far,
cumulative_bookings / GREATEST (1, days_since_first_flight) as booking_rate_since_first_flight, 
remaining_bookings / GREATEST(1, days_to_end_of_dataset) as rate_remaining,
remaining_bookings / GREATEST(1, days_to_last_flight) as rate_to_last_flight
FROM
(SELECT account_id, booking_id, updat_ts, cumulative_bookings, actual_departure, actual_arrival,
 CASE WHEN (actual_arrival is NULL) then max(actual_arrival) over (partition by account_id 
RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) else actual_arrival end as actual_arrival_filled,
remaining_bookings, Missed_flight_flag,scheduled_departure, scheduled_arrival, max_rn, 
mins_since_last_flight_arrival,min_flight_time, max_flight_time, 
round(extract(epoch from (updat_ts - min(updat_ts) over (order by updat_ts)))/(24*60*60))
 as days_since_start_of_dataset, round(extract(epoch from (scheduled_departure - min_flight_time))/(24*60*60))
 as days_since_first_flight, round(extract(epoch from (max_flight_time - scheduled_departure))/(24*60*60)) 
 as days_to_last_flight,round(extract(epoch from (max(updat_ts) over (order by updat_ts RANGE BETWEEN UNBOUNDED
													  PRECEDING AND UNBOUNDED FOLLOWING) - updat_ts))/(24*60*60))
as days_to_end_of_dataset, row_number, sum(Missed_flight_flag)
over (partition by account_id order by updat_ts) as cumulative_missed_flights_by_account,
count(actual_arrival) over
 (partition by account_id order by actual_arrival) as cum_arrival_count FROM
(SELECT account_id, booking_id, updat_ts, cumulative_bookings, actual_departure, actual_arrival, 
 scheduled_departure, scheduled_arrival, case when min(mins_since_last_flight_arrival) over(partition by booking_id) < 5 THEN 1 
ELSE 0 END as Missed_flight_flag, mins_since_last_flight_arrival, min_flight_time, max_flight_time, row_number, max(row_number) over (partition by booking_id)
 as max_rn, max(cumulative_bookings) over (partition by account_id) - cumulative_bookings as remaining_bookings FROM
(SELECT account_id, updat_ts, cumulative_bookings, scheduled_departure, scheduled_arrival, booking_id,
flight_id, actual_departure, actual_arrival, round(extract(epoch from(actual_departure - lag(actual_arrival)
																over(partition by booking_id ORDER BY  leg_num)))/60, 0)
as mins_since_last_flight_arrival, row_number() over (partition by booking_id order by updat_ts), 
 min(scheduled_departure) over (order by scheduled_departure) as min_flight_time, max(scheduled_departure) over 
 (order by scheduled_departure RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as max_flight_time
FROM
((SELECT booking_id as book_id, account_id, update_ts as updat_ts, 
count(booking_id) over (partition by account_id order by update_ts) as cumulative_bookings
FROM postgres_air.booking
WHERE account_id < 1000
ORDER BY account_id
)a
LEFT JOIN
(SELECT booking_id, flight_id as flght_id, booking_leg_id,leg_num FROM postgres_air.booking_leg)b
on a.book_id = b.booking_id
)aa
LEFT JOIN
(SELECT * FROM postgres_air.flight)c
on aa.flght_id = c.flight_id
ORDER BY account_id, updat_ts
)bb
)cc
WHERE row_number = max_rn
)dd
)ee
JOIN
(SELECT account_id, booking_id, updat_ts, actual_arrival_filled, count(actual_arrival_filled > updat_ts) over (partition by account_id),
sum(case when (updat_ts > actual_arrival_filled) then 1 else 0 end) over (partition by account_id order by updat_ts)+1 as count_2,
row_number() over(partition by account_id order by actual_arrival_filled) as rn, cumulative_bookings, actual_departure,
actual_arrival, remaining_bookings, Missed_flight_flag,scheduled_departure, scheduled_arrival, max_rn, 
mins_since_last_flight_arrival,min_flight_time, max_flight_time, days_since_start_of_dataset, days_to_end_of_dataset, row_number,
cumulative_missed_flights_by_account, days_since_first_flight, days_to_last_flight, 
cumulative_bookings / GREATEST (1, days_since_start_of_dataset)as booking_rate_so_far,
cumulative_bookings / GREATEST (1, days_since_first_flight) as booking_rate_since_first_flight, 
remaining_bookings / GREATEST(1, days_to_end_of_dataset) as rate_remaining,
remaining_bookings / GREATEST(1, days_to_last_flight) as rate_to_last_flight
FROM
(SELECT account_id, booking_id, updat_ts, cumulative_bookings, actual_departure, actual_arrival,
 CASE WHEN (actual_arrival is NULL) then max(actual_arrival) over (partition by account_id 
RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) else actual_arrival end as actual_arrival_filled,
remaining_bookings, Missed_flight_flag,scheduled_departure, scheduled_arrival, max_rn, 
mins_since_last_flight_arrival,min_flight_time, max_flight_time, 
round(extract(epoch from (updat_ts - min(updat_ts) over (order by updat_ts)))/(24*60*60))
 as days_since_start_of_dataset, round(extract(epoch from (scheduled_departure - min_flight_time))/(24*60*60))
 as days_since_first_flight, round(extract(epoch from (max_flight_time - scheduled_departure))/(24*60*60)) 
 as days_to_last_flight,round(extract(epoch from (max(updat_ts) over (order by updat_ts RANGE BETWEEN UNBOUNDED
													  PRECEDING AND UNBOUNDED FOLLOWING) - updat_ts))/(24*60*60))
as days_to_end_of_dataset, row_number, sum(Missed_flight_flag)
over (partition by account_id order by updat_ts) as cumulative_missed_flights_by_account,
count(actual_arrival) over
 (partition by account_id order by actual_arrival) as cum_arrival_count FROM
(SELECT account_id, booking_id, updat_ts, cumulative_bookings, actual_departure, actual_arrival, 
 scheduled_departure, scheduled_arrival, case when min(mins_since_last_flight_arrival) over(partition by booking_id) < 5 THEN 1 
ELSE 0 END as Missed_flight_flag, mins_since_last_flight_arrival, min_flight_time, max_flight_time, row_number, max(row_number) over (partition by booking_id)
 as max_rn, max(cumulative_bookings) over (partition by account_id) - cumulative_bookings as remaining_bookings FROM
(SELECT account_id, updat_ts, cumulative_bookings, scheduled_departure, scheduled_arrival, booking_id,
flight_id, actual_departure, actual_arrival, round(extract(epoch from(actual_departure - lag(actual_arrival)
																over(partition by booking_id ORDER BY  leg_num)))/60, 0)
as mins_since_last_flight_arrival, row_number() over (partition by booking_id order by updat_ts), 
 min(scheduled_departure) over (order by scheduled_departure) as min_flight_time, max(scheduled_departure) over 
 (order by scheduled_departure RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as max_flight_time
FROM
((SELECT booking_id as book_id, account_id, update_ts as updat_ts, 
count(booking_id) over (partition by account_id order by update_ts) as cumulative_bookings
FROM postgres_air.booking
WHERE account_id < 1000
ORDER BY account_id
)z
LEFT JOIN
(SELECT booking_id, flight_id as flght_id, booking_leg_id,leg_num FROM postgres_air.booking_leg)y
on z.book_id = y.booking_id
)zz
LEFT JOIN
(SELECT * FROM postgres_air.flight)x
on zz.flght_id = x.flight_id
ORDER BY account_id, updat_ts
)yy
)xx
WHERE row_number = max_rn
)ww
)vv
on ee.account_id = vv.account_id
and ee.count_2 = vv.rn
WHERE extract(epoch from(ee.updat_ts - vv.actual_arrival_filled)) > 0
#

SELECT distinct on(account_id, updat_ts) account_id, updat_ts, actual_arrival, hours_to_next_booking FROM
(SELECT distinct on(account_id, actual_arrival) account_id, updat_ts, actual_arrival, hours_to_next_booking FROM
(SELECT ee.account_id, ee.updat_ts, ee.count_2, vv.actual_arrival, ee.rn, ee.mins_since_last_flight_arrival,
extract(epoch from (ee.updat_ts - vv.actual_arrival))/3600 as hours_to_next_booking FROM
(SELECT account_id, booking_id, updat_ts, actual_arrival_filled, count(actual_arrival_filled > updat_ts) over (partition by account_id),
sum(case when (updat_ts > actual_arrival_filled) then 1 else 0 end) over (partition by account_id order by updat_ts)+1 as count_2,
row_number() over(partition by account_id order by actual_arrival_filled) as rn, cumulative_bookings, actual_departure,
actual_arrival, remaining_bookings, Missed_flight_flag,scheduled_departure, scheduled_arrival, max_rn, 
mins_since_last_flight_arrival,min_flight_time, max_flight_time, days_since_start_of_dataset, days_to_end_of_dataset, row_number,
cumulative_missed_flights_by_account, days_since_first_flight, days_to_last_flight, 
cumulative_bookings / GREATEST (1, days_since_start_of_dataset)as booking_rate_so_far,
cumulative_bookings / GREATEST (1, days_since_first_flight) as booking_rate_since_first_flight, 
remaining_bookings / GREATEST(1, days_to_end_of_dataset) as rate_remaining,
remaining_bookings / GREATEST(1, days_to_last_flight) as rate_to_last_flight
FROM
(SELECT account_id, booking_id, updat_ts, cumulative_bookings, actual_departure, actual_arrival,
 CASE WHEN (actual_arrival is NULL) then max(actual_arrival) over (partition by account_id 
RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) else actual_arrival end as actual_arrival_filled,
remaining_bookings, Missed_flight_flag,scheduled_departure, scheduled_arrival, max_rn, 
mins_since_last_flight_arrival,min_flight_time, max_flight_time, 
round(extract(epoch from (updat_ts - min(updat_ts) over (order by updat_ts)))/(24*60*60))
 as days_since_start_of_dataset, round(extract(epoch from (scheduled_departure - min_flight_time))/(24*60*60))
 as days_since_first_flight, round(extract(epoch from (max_flight_time - scheduled_departure))/(24*60*60)) 
 as days_to_last_flight,round(extract(epoch from (max(updat_ts) over (order by updat_ts RANGE BETWEEN UNBOUNDED
													  PRECEDING AND UNBOUNDED FOLLOWING) - updat_ts))/(24*60*60))
as days_to_end_of_dataset, row_number, sum(Missed_flight_flag)
over (partition by account_id order by updat_ts) as cumulative_missed_flights_by_account,
count(actual_arrival) over
 (partition by account_id order by actual_arrival) as cum_arrival_count FROM
(SELECT account_id, booking_id, updat_ts, cumulative_bookings, actual_departure, actual_arrival, 
 scheduled_departure, scheduled_arrival, case when min(mins_since_last_flight_arrival) over(partition by booking_id) < 5 THEN 1 
ELSE 0 END as Missed_flight_flag, mins_since_last_flight_arrival, min_flight_time, max_flight_time, row_number, max(row_number) over (partition by booking_id)
 as max_rn, max(cumulative_bookings) over (partition by account_id) - cumulative_bookings as remaining_bookings FROM
(SELECT account_id, updat_ts, cumulative_bookings, scheduled_departure, scheduled_arrival, booking_id,
flight_id, actual_departure, actual_arrival, round(extract(epoch from(actual_departure - lag(actual_arrival)
																over(partition by booking_id ORDER BY  leg_num)))/60, 0)
as mins_since_last_flight_arrival, row_number() over (partition by booking_id order by updat_ts), 
 min(scheduled_departure) over (order by scheduled_departure) as min_flight_time, max(scheduled_departure) over 
 (order by scheduled_departure RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as max_flight_time
FROM
((SELECT booking_id as book_id, account_id, update_ts as updat_ts, 
count(booking_id) over (partition by account_id order by update_ts) as cumulative_bookings
FROM postgres_air.booking
WHERE account_id < 1000
ORDER BY account_id
)a
LEFT JOIN
(SELECT booking_id, flight_id as flght_id, booking_leg_id,leg_num FROM postgres_air.booking_leg)b
on a.book_id = b.booking_id
)aa
LEFT JOIN
(SELECT * FROM postgres_air.flight)c
on aa.flght_id = c.flight_id
ORDER BY account_id, updat_ts
)bb
)cc
WHERE row_number = max_rn
)dd
)ee
LEFT JOIN
(SELECT account_id, updat_ts, cumulative_bookings, actual_departure,
actual_arrival, scheduled_departure, scheduled_arrival, max_rn
FROM
(SELECT account_id, booking_id, updat_ts, cumulative_bookings, actual_departure, actual_arrival, 
 scheduled_departure, scheduled_arrival, min_flight_time, max_flight_time, row_number, 
 max(row_number) over (partition by booking_id) as max_rn FROM
(SELECT account_id, updat_ts, cumulative_bookings, scheduled_departure, scheduled_arrival, booking_id,
flight_id, actual_departure, actual_arrival, round(extract(epoch from(actual_departure - lag(actual_arrival)
																over(partition by booking_id ORDER BY  leg_num)))/60, 0)
as mins_since_last_flight_arrival, row_number() over (partition by booking_id order by updat_ts), 
 min(scheduled_departure) over (order by scheduled_departure) as min_flight_time, max(scheduled_departure) over 
 (order by scheduled_departure RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as max_flight_time
FROM
((SELECT booking_id as book_id, account_id, update_ts as updat_ts, 
count(booking_id) over (partition by account_id order by update_ts) as cumulative_bookings
FROM postgres_air.booking
WHERE account_id < 1000
ORDER BY account_id
)z
LEFT JOIN
(SELECT booking_id, flight_id as flght_id, booking_leg_id,leg_num FROM postgres_air.booking_leg)y
on z.book_id = y.booking_id
)zz
LEFT JOIN
(SELECT * FROM postgres_air.flight)x
on zz.flght_id = x.flight_id
ORDER BY account_id, updat_ts
)yy
)xx
WHERE row_number = max_rn
and actual_arrival is not NULL
ORDER BY account_id, actual_arrival
)vv
on ee.account_id = vv.account_id
and ee.updat_ts > vv.actual_arrival
ORDER BY account_id, actual_arrival, hours_to_next_booking
)aaa
)bbb
order by account_id, updat_ts, hours_to_next_booking


CREATE TABLE postgres_air.last_flight_by_account_id AS
SELECT * FROM
(SELECT account_id, booking_id, flight_id, actual_arrival, max(actual_arrival) over (partition by account_id) as max_arrival,
end_of_dataset
FROM
(
(
(
(SELECT account_id FROM postgres_air.account
)a
LEFT JOIN
(SELECT account_id as acc, booking_id, max(update_ts) over () as end_of_dataset FROM postgres_air.booking
)b
on a.account_id = b.acc
)c
LEFT JOIN
(SELECT booking_id as boo, flight_id FROM postgres_air.booking_leg)d
on c.booking_id = d.boo
)e
LEFT JOIN
(SELECT flight_id as fli, scheduled_arrival, actual_arrival FROM postgres_air.flight)f
on e.flight_id = f.fli
)
)g
WHERE actual_arrival = max_arrival





CREATE TABLE postgres_air.time_to_next_flight AS
SELECT distinct on(account_id, updat_ts) account_id, updat_ts, actual_arrival, hours_to_next_booking, booking_id,
 remaining_bookings, Missed_flight_flag, scheduled_departure, scheduled_arrival, min_flight_time, max_flight_time, 
 days_since_start_of_dataset, days_to_end_of_dataset FROM
(SELECT distinct on(account_id, actual_arrival) account_id, updat_ts, actual_arrival, hours_to_next_booking, booking_id,
 remaining_bookings, Missed_flight_flag, scheduled_departure, scheduled_arrival, min_flight_time, max_flight_time, 
 days_since_start_of_dataset, days_to_end_of_dataset FROM
(SELECT ee.account_id, ee.updat_ts, ee.count_2, vv.actual_arrival, ee.rn, ee.mins_since_last_flight_arrival,
ee.booking_id, ee.remaining_bookings, ee.Missed_flight_flag,ee.scheduled_departure, ee.scheduled_arrival,  
ee.min_flight_time, ee.max_flight_time, ee.days_since_start_of_dataset, ee.days_to_end_of_dataset, 
 extract(epoch from (ee.updat_ts - vv.actual_arrival))/3600 as hours_to_next_booking FROM
(SELECT account_id, booking_id, updat_ts, actual_arrival_filled, count(actual_arrival_filled > updat_ts) over (partition by account_id),
sum(case when (updat_ts > actual_arrival_filled) then 1 else 0 end) over (partition by account_id order by updat_ts)+1 as count_2,
row_number() over(partition by account_id order by actual_arrival_filled) as rn, cumulative_bookings, actual_departure,
actual_arrival, remaining_bookings, Missed_flight_flag,scheduled_departure, scheduled_arrival, max_rn, 
mins_since_last_flight_arrival,min_flight_time, max_flight_time, days_since_start_of_dataset, days_to_end_of_dataset, row_number,
cumulative_missed_flights_by_account, days_since_first_flight, days_to_last_flight, 
cumulative_bookings / GREATEST (1, days_since_start_of_dataset)as booking_rate_so_far,
cumulative_bookings / GREATEST (1, days_since_first_flight) as booking_rate_since_first_flight, 
remaining_bookings / GREATEST(1, days_to_end_of_dataset) as rate_remaining,
remaining_bookings / GREATEST(1, days_to_last_flight) as rate_to_last_flight
FROM
(SELECT account_id, booking_id, updat_ts, cumulative_bookings, actual_departure, actual_arrival,
 CASE WHEN (actual_arrival is NULL) then max(actual_arrival) over (partition by account_id 
RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) else actual_arrival end as actual_arrival_filled,
remaining_bookings, Missed_flight_flag,scheduled_departure, scheduled_arrival, max_rn, 
mins_since_last_flight_arrival,min_flight_time, max_flight_time, 
round(extract(epoch from (updat_ts - min(updat_ts) over (order by updat_ts)))/(24*60*60))
 as days_since_start_of_dataset, round(extract(epoch from (scheduled_departure - min_flight_time))/(24*60*60))
 as days_since_first_flight, round(extract(epoch from (max_flight_time - scheduled_departure))/(24*60*60)) 
 as days_to_last_flight,round(extract(epoch from (max(updat_ts) over (order by updat_ts RANGE BETWEEN UNBOUNDED
													  PRECEDING AND UNBOUNDED FOLLOWING) - updat_ts))/(24*60*60))
as days_to_end_of_dataset, row_number, sum(Missed_flight_flag)
over (partition by account_id order by updat_ts) as cumulative_missed_flights_by_account,
count(actual_arrival) over
 (partition by account_id order by actual_arrival) as cum_arrival_count FROM
(SELECT account_id, booking_id, updat_ts, cumulative_bookings, actual_departure, actual_arrival, 
 scheduled_departure, scheduled_arrival, case when min(mins_since_last_flight_arrival) over(partition by booking_id) < 5 THEN 1 
ELSE 0 END as Missed_flight_flag, mins_since_last_flight_arrival, min_flight_time, max_flight_time, row_number, max(row_number) over (partition by booking_id)
 as max_rn, max(cumulative_bookings) over (partition by account_id) - cumulative_bookings as remaining_bookings FROM
(SELECT account_id, updat_ts, cumulative_bookings, scheduled_departure, scheduled_arrival, booking_id,
flight_id, actual_departure, actual_arrival, round(extract(epoch from(actual_departure - lag(actual_arrival)
																over(partition by booking_id ORDER BY  leg_num)))/60, 0)
as mins_since_last_flight_arrival, row_number() over (partition by booking_id order by updat_ts), 
 min(scheduled_departure) over (order by scheduled_departure) as min_flight_time, max(scheduled_departure) over 
 (order by scheduled_departure RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as max_flight_time
FROM
((SELECT booking_id as book_id, account_id, update_ts as updat_ts, 
count(booking_id) over (partition by account_id order by update_ts) as cumulative_bookings
FROM postgres_air.booking
ORDER BY account_id
)a
LEFT JOIN
(SELECT booking_id, flight_id as flght_id, booking_leg_id,leg_num FROM postgres_air.booking_leg)b
on a.book_id = b.booking_id
)aa
LEFT JOIN
(SELECT * FROM postgres_air.flight)c
on aa.flght_id = c.flight_id
ORDER BY account_id, updat_ts
)bb
)cc
WHERE row_number = max_rn
)dd
)ee
LEFT JOIN
(SELECT account_id, actual_arrival
FROM
(SELECT account_id, booking_id, updat_ts, cumulative_bookings, actual_departure, actual_arrival, 
 scheduled_departure, scheduled_arrival, min_flight_time, row_number, 
 max(row_number) over (partition by booking_id) as max_rn FROM
(SELECT account_id, updat_ts, cumulative_bookings, scheduled_departure, scheduled_arrival, booking_id,
flight_id, actual_departure, actual_arrival, round(extract(epoch from(actual_departure - lag(actual_arrival)
																over(partition by booking_id ORDER BY  leg_num)))/60, 0)
as mins_since_last_flight_arrival, row_number() over (partition by booking_id order by updat_ts), 
 min(scheduled_departure) over (order by scheduled_departure) as min_flight_time
FROM
((SELECT booking_id as book_id, account_id, update_ts as updat_ts, 
count(booking_id) over (partition by account_id order by update_ts) as cumulative_bookings
FROM postgres_air.booking
ORDER BY account_id
)z
LEFT JOIN
(SELECT booking_id, flight_id as flght_id, booking_leg_id,leg_num FROM postgres_air.booking_leg)y
on z.book_id = y.booking_id
)zz
LEFT JOIN
(SELECT * FROM postgres_air.flight)x
on zz.flght_id = x.flight_id
ORDER BY account_id, updat_ts
)yy
)xx
WHERE row_number = max_rn
and actual_arrival is not NULL
ORDER BY account_id, actual_arrival
)vv
on ee.account_id = vv.account_id
and ee.updat_ts > vv.actual_arrival
ORDER BY account_id, actual_arrival, hours_to_next_booking
)aaa
WHERE hours_to_next_booking IS NOT NULL
OR missed_flight_flag = 1
)bbb
order by account_id, updat_ts, hours_to_next_booking


CREATE TABLE postgres_air.time_to_next_flight_2 AS
SELECT distinct on(account_id, updat_ts) account_id, updat_ts, actual_arrival, hours_to_next_booking, booking_id, booking_id_2,
 remaining_bookings, Missed_flight_flag, scheduled_departure, scheduled_arrival, min_flight_time, max_flight_time, 
 days_since_start_of_dataset, days_to_end_of_dataset FROM
(SELECT distinct on(account_id, actual_arrival) account_id, updat_ts, actual_arrival, hours_to_next_booking, booking_id, booking_id_2,
 remaining_bookings, Missed_flight_flag, scheduled_departure, scheduled_arrival, min_flight_time, max_flight_time, 
 days_since_start_of_dataset, days_to_end_of_dataset FROM
(SELECT ee.account_id, ee.updat_ts, ee.count_2, vv.actual_arrival, vv.booking_id as booking_id_2, ee.rn, ee.mins_since_last_flight_arrival,
ee.booking_id, ee.remaining_bookings, ee.Missed_flight_flag,ee.scheduled_departure, ee.scheduled_arrival,  
ee.min_flight_time, ee.max_flight_time, ee.days_since_start_of_dataset, ee.days_to_end_of_dataset, 
 extract(epoch from (ee.updat_ts - vv.actual_arrival))/3600 as hours_to_next_booking FROM
(SELECT account_id, booking_id, updat_ts, actual_arrival_filled, count(actual_arrival_filled > updat_ts) over (partition by account_id),
sum(case when (updat_ts > actual_arrival_filled) then 1 else 0 end) over (partition by account_id order by updat_ts)+1 as count_2,
row_number() over(partition by account_id order by actual_arrival_filled) as rn, cumulative_bookings, actual_departure,
actual_arrival, remaining_bookings, Missed_flight_flag,scheduled_departure, scheduled_arrival, max_rn, 
mins_since_last_flight_arrival,min_flight_time, max_flight_time, days_since_start_of_dataset, days_to_end_of_dataset, row_number,
cumulative_missed_flights_by_account, days_since_first_flight, days_to_last_flight, 
cumulative_bookings / GREATEST (1, days_since_start_of_dataset)as booking_rate_so_far,
cumulative_bookings / GREATEST (1, days_since_first_flight) as booking_rate_since_first_flight, 
remaining_bookings / GREATEST(1, days_to_end_of_dataset) as rate_remaining,
remaining_bookings / GREATEST(1, days_to_last_flight) as rate_to_last_flight
FROM
(SELECT account_id, booking_id, updat_ts, cumulative_bookings, actual_departure, actual_arrival,
 CASE WHEN (actual_arrival is NULL) then max(actual_arrival) over (partition by account_id 
RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) else actual_arrival end as actual_arrival_filled,
remaining_bookings, Missed_flight_flag,scheduled_departure, scheduled_arrival, max_rn, 
mins_since_last_flight_arrival,min_flight_time, max_flight_time, 
round(extract(epoch from (updat_ts - min(updat_ts) over (order by updat_ts)))/(24*60*60))
 as days_since_start_of_dataset, round(extract(epoch from (scheduled_departure - min_flight_time))/(24*60*60))
 as days_since_first_flight, round(extract(epoch from (max_flight_time - scheduled_departure))/(24*60*60)) 
 as days_to_last_flight,round(extract(epoch from (max(updat_ts) over (order by updat_ts RANGE BETWEEN UNBOUNDED
													  PRECEDING AND UNBOUNDED FOLLOWING) - updat_ts))/(24*60*60))
as days_to_end_of_dataset, row_number, sum(Missed_flight_flag)
over (partition by account_id order by updat_ts) as cumulative_missed_flights_by_account,
count(actual_arrival) over
 (partition by account_id order by actual_arrival) as cum_arrival_count FROM
(SELECT account_id, booking_id, updat_ts, cumulative_bookings, actual_departure, actual_arrival, 
 scheduled_departure, scheduled_arrival, case when min(mins_since_last_flight_arrival) over(partition by booking_id) < 5 THEN 1 
ELSE 0 END as Missed_flight_flag, mins_since_last_flight_arrival, min_flight_time, max_flight_time, row_number, max(row_number) over (partition by booking_id)
 as max_rn, max(cumulative_bookings) over (partition by account_id) - cumulative_bookings as remaining_bookings FROM
(SELECT account_id, updat_ts, cumulative_bookings, scheduled_departure, scheduled_arrival, booking_id,
flight_id, actual_departure, actual_arrival, round(extract(epoch from(actual_departure - lag(actual_arrival)
																over(partition by booking_id ORDER BY  leg_num)))/60, 0)
as mins_since_last_flight_arrival, row_number() over (partition by booking_id order by updat_ts), 
 min(scheduled_departure) over (order by scheduled_departure) as min_flight_time, max(scheduled_departure) over 
 (order by scheduled_departure RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as max_flight_time
FROM
((SELECT booking_id as book_id, account_id, update_ts as updat_ts, 
count(booking_id) over (partition by account_id order by update_ts) as cumulative_bookings
FROM postgres_air.booking
ORDER BY account_id
)a
LEFT JOIN
(SELECT booking_id, flight_id as flght_id, booking_leg_id,leg_num FROM postgres_air.booking_leg)b
on a.book_id = b.booking_id
)aa
LEFT JOIN
(SELECT * FROM postgres_air.flight)c
on aa.flght_id = c.flight_id
ORDER BY account_id, updat_ts
)bb
)cc
WHERE row_number = max_rn
)dd
)ee
LEFT JOIN
(SELECT account_id, actual_arrival, booking_id
FROM
(SELECT account_id, booking_id, updat_ts, cumulative_bookings, actual_departure, actual_arrival, 
 scheduled_departure, scheduled_arrival, min_flight_time, row_number, 
 max(row_number) over (partition by booking_id) as max_rn FROM
(SELECT account_id, updat_ts, cumulative_bookings, scheduled_departure, scheduled_arrival, booking_id,
flight_id, actual_departure, actual_arrival, round(extract(epoch from(actual_departure - lag(actual_arrival)
																over(partition by booking_id ORDER BY  leg_num)))/60, 0)
as mins_since_last_flight_arrival, row_number() over (partition by booking_id order by updat_ts), 
 min(scheduled_departure) over (order by scheduled_departure) as min_flight_time
FROM
((SELECT booking_id as book_id, account_id, update_ts as updat_ts, 
count(booking_id) over (partition by account_id order by update_ts) as cumulative_bookings
FROM postgres_air.booking
ORDER BY account_id
)z
LEFT JOIN
(SELECT booking_id, flight_id as flght_id, booking_leg_id,leg_num FROM postgres_air.booking_leg)y
on z.book_id = y.booking_id
)zz
LEFT JOIN
(SELECT * FROM postgres_air.flight)x
on zz.flght_id = x.flight_id
ORDER BY account_id, updat_ts
)yy
)xx
WHERE row_number = max_rn
and actual_arrival is not NULL
ORDER BY account_id, actual_arrival
)vv
on ee.account_id = vv.account_id
and ee.updat_ts > vv.actual_arrival
ORDER BY account_id, actual_arrival, hours_to_next_booking
)aaa
)bbb
order by account_id, updat_ts, hours_to_next_booking

SELECT case when (max_arrival_by_account > max_booking) then 1 else 0 end as censored_id, account_id, booking_id, flight_id, update_ts, max(update_ts) over (partition by account_id) as max_booking,
 max(actual_arrival) over (partition by account_id) as max_arrival_by_account, actual_arrival, scheduled_arrival,
 end_of_dataset, last_flight, case when min(mins_since_last_flight_arrival) over(partition by booking_id) < 5 THEN 1 ELSE 0 END as Missed_flight_flag FROM
(SELECT account_id, booking_id, flight_id, update_ts, max(update_ts) over (partition by account_id) as max_booking,
 max(actual_arrival) over (partition by account_id) as max_arrival_by_account, actual_arrival, scheduled_arrival,
 end_of_dataset, last_flight, 

round(extract(epoch from(actual_departure - lag(actual_arrival)
																over(partition by booking_id ORDER BY  leg_num)))/60, 0)
as mins_since_last_flight_arrival
FROM
(
(
(
(SELECT account_id FROM postgres_air.account
)a
LEFT JOIN
(SELECT account_id as acc, booking_id, update_ts, max(update_ts) over () as end_of_dataset FROM postgres_air.booking
)b
on a.account_id = b.acc
)c
LEFT JOIN
(SELECT booking_id as boo, flight_id, leg_num FROM postgres_air.booking_leg)d
on c.booking_id = d.boo
)e
LEFT JOIN
(SELECT flight_id as fli, scheduled_arrival, actual_arrival, actual_departure, max(actual_arrival) over () as last_flight FROM postgres_air.flight)f
on e.flight_id = f.fli
)
)g
WHERE max_arrival_by_account > max_booking
AND actual_arrival = max_arrival_by_account

