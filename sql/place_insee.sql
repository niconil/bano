WITH
a AS
(SELECT	ST_Transform(pt.way,4326) pt_geo,
		pt.place,
		pt.name,
		pt.tags->'ref:FR:FANTOIR' fantoir,
		pt.tags,
		p.tags->'ref:INSEE' insee_com
 FROM	planet_osm_polygon	p
 JOIN	planet_osm_point 	pt
 ON		ST_Intersects(pt.way, p.way)
 WHERE	p.tags ? 'ref:INSEE'			AND
		p.tags->'ref:INSEE'='__com__'	AND
		pt.place != ''	AND
		pt.name != '')
SELECT 	ST_X(pt_geo)::character varying,
		ST_Y(pt_geo)::character varying,
		place,
		name,
		fantoir,
		'0', --ld_bati
		tags,
		insee_com
FROM	a