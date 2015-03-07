# script écrit et maintenu par cquest@openstreetmap.fr

# dédoublement des adresses multiple OSM (séparées par ';' '-' ',' ou 'à')
psql cadastre -q -c "insert into cumul_adresses select geometrie, trim( both from regexp_split_to_table(numero,';|-|à|,')), voie_cadastre, voie_osm, fantoir, insee_com, cadastre_com, dept, code_postal, source, batch_import_id, voie_fantoir from cumul_adresses where numero ~ ';|-|à|,' and insee_com like '$1%' and source='OSM';"
psql cadastre -q -c "delete from cumul_adresses where numero ~ ';|-|à|,' and insee_com like '$1%' and source='OSM';"

rm -f tmp-$1-full.json

echo "`date +%H:%M:%S` Voie non rapprochées $1"
# export fantoir_voie (pour les voies non rapprochées) + cumul_adresse (ponctuel adresse) > json
psql cadastre -t -A -c " \
WITH v as (select code_insee as insee_com, code_insee || id_voie || cle_rivoli as fantoir from fantoir_voie f left join cumul_voies v on (f.code_insee=v.insee_com and v.fantoir = code_insee || id_voie || cle_rivoli) where v.fantoir is null and code_insee like '$1%')
SELECT '{\"id\": \"' || osm.fantoir || CASE WHEN coalesce(cp.postal_cod, cad.code_postal)!=cad.code_postal THEN ('_' || cp.postal_cod) ELSE '' END || '\",\"type\": \"street\",\"name\": \"' || replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(max(osm.voie_cadastre),'^IMP ','Impasse '),'^RTE ','Route '),'^ALL ','Allée '),'^PL ','Place '),'^PLA ','Place '),'^AV ','Avenue '),'^LOT ','Lotissement '),'^RES ','Résidence '),'^CHEM ','Chemin '),'^RLE ','Ruelle '),'^BD ','Boulevard '),'^SQ ','Square '),'^PAS ','Passage '),'^SEN ','Sentier '),'^CRS ','Cours '),'^TRA ','Traverse '),'^MTE ','Montée '),'^RPT ','Rond-point '),'^HAM ','Hameau '),'^VLA ','Villa '),'^PROM ','Promenade '),'^ESP ','Esplanade '),'^FG ','Faubourg '),'^TSSE ','Terrasse '),'^CTRE ','Centre '),'^PASS ','Passerelle '),'^FRM ','Ferme '),' GAL ',' Général '),' MAL ',' Maréchal '),' ST ',' Saint '),' STE ',' Sainte '),' PDT ',' Président '),' HT ',' Haut '),' HTE ',' Haute '),' VX ',' Vieux '),' PTE ',' Petite '),'\"',''),'’',chr(39)) || '\",\"postcode\": \"' || coalesce(cp.postal_cod, cad.code_postal) || CASE WHEN replace(lower(cp.nom),'-',' ') != replace(lower(c.nom),'-',' ') THEN '\",\"post_office\": \"' || cp.nom ELSE '' END || '\",\"lat\": \"' || round(st_y(st_centroid(st_convexhull(ST_Collect(osm.geometrie))))::numeric,6) || '\",\"lon\": \"' || round(st_x(st_centroid(st_convexhull(ST_Collect(osm.geometrie))))::numeric,6) || '\",\"city\": \"' || c.nom || '\",\"departement\": \"' || cog.nom_dep || '\", \"region\": \"' || cog.nom_reg || '\",\"importance\": '|| round(log((CASE WHEN (cad.code_postal LIKE '75%' OR g.statut LIKE 'Capital%') THEN 6 WHEN (cad.code_postal LIKE '690%' OR cad.code_postal LIKE '130%' OR g.statut = 'Préfecture de régi') THEN 5 WHEN g.statut='Préfecture' THEN 4 WHEN g.statut LIKE 'Sous-pr%' THEN 3 WHEN g.statut='Chef-lieu canton' THEN 2 ELSE 1 END)+log(g.population+1)/3)::numeric*log(1+log(count(osm.*)+1)+log(st_length(st_longestline(st_convexhull(ST_Collect(osm.geometrie)),st_convexhull(ST_Collect(osm.geometrie)))::geography)+1)+log(CASE WHEN max(osm.voie_cadastre) like 'Boulevard%' THEN 4 WHEN max(osm.voie_cadastre) LIKE 'Place%' THEN 4 WHEN max(osm.voie_cadastre) LIKE 'Espl%' THEN 4 WHEN max(osm.voie_cadastre) LIKE 'Av%' THEN 3 WHEN max(osm.voie_cadastre) LIKE 'Rue %' THEN 2 ELSE 1 END))::numeric,4) ||' ,\"housenumbers\":' || concat('{',string_agg(concat('\"',replace(replace(replace(osm.numero,' ',''),'\"',''),'\\',''),'\": {\"lat\": ',round(st_y(osm.geometrie)::numeric,6),',\"lon\": ',round(st_x(osm.geometrie)::numeric,6),'}'), ','),'}}') AS sjson
FROM v
LEFT JOIN cumul_adresses osm ON (osm.fantoir=v.fantoir)
JOIN communes c ON (c.insee=v.insee_com)
JOIN code_cadastre cad ON (cad.insee_com=v.insee_com)
JOIN
  (SELECT fantoir,
          replace(numero,' ','') AS num,
          max(SOURCE) AS src
   FROM cumul_adresses
   GROUP BY 1,
            2) AS b ON (b.fantoir=osm.fantoir
                        AND osm.SOURCE=b.src
                        AND b.num=replace(osm.numero,' ',''))
LEFT JOIN (select dep, nom_dep, nom_reg from cog group by dep, nom_dep, nom_reg) as cog ON (cog.dep=left(v.insee_com,2) or cog.dep=left(v.insee_com,3))
LEFT JOIN geofla_plus g ON (g.insee=v.insee_com)
LEFT JOIN postal_code cp ON (cp.insee=v.insee_com AND ST_Contains(cp.wkb_geometry, osm.geometrie))
WHERE osm.fantoir IS NOT NULL
  AND osm.numero ~ '^[0-9]{1,4}( ?[A-Z]?.*)?'
  AND osm.numero !~'.[0-9 \\.\\-]{9,}'
GROUP BY osm.fantoir,
         cad.code_postal, cp.postal_cod,
         c.nom, cp.nom,
         cog.nom_dep,
         cog.nom_reg,
         g.statut,
         g.population
ORDER BY osm.fantoir;
" >> tmp-$1-full.json

echo "`date +%H:%M:%S` Voie rapprochées $1"
# export cumul_voie (position centre de voirie) + cumul_adresse (ponctuel adresse) > json
psql cadastre -t -A -c " \
SELECT '{\"id\": \"' || v.fantoir || CASE WHEN coalesce(cp.postal_cod, cad.code_postal)!=cad.code_postal THEN ('_' || cp.postal_cod) ELSE '' END || '\",\"type\": \"street\",\"name\": \"' || replace(replace(v.voie_osm,'\"',''),'’',chr(39)) || '\",\"postcode\": \"' || coalesce(cp.postal_cod, cad.code_postal) || CASE WHEN replace(lower(cp.nom),'-',' ') != replace(lower(c.nom),'-',' ') THEN '\",\"post_office\": \"' || cp.nom ELSE '' END || '\",\"lat\": \"' || round(st_y(v.geometrie)::numeric,6) || '\",\"lon\": \"' || round(st_x(v.geometrie)::numeric,6) || '\",\"city\": \"' || c.nom || '\",\"departement\": \"' || cog.nom_dep || '\", \"region\": \"' || cog.nom_reg || '\",\"importance\": '|| round(log((CASE WHEN (cad.code_postal LIKE '75%' OR g.statut LIKE 'Capital%') THEN 6 WHEN (cad.code_postal LIKE '690%' OR cad.code_postal LIKE '130%' OR g.statut = 'Préfecture de régi') THEN 5 WHEN g.statut='Préfecture' THEN 4 WHEN g.statut LIKE 'Sous-pr%' THEN 3 WHEN g.statut='Chef-lieu canton' THEN 2 ELSE 1 END)+log(g.population+1)/3)::numeric*log(1+log(count(osm.*)+1)+log(st_length(st_longestline(st_convexhull(ST_Collect(osm.geometrie)),st_convexhull(ST_Collect(osm.geometrie)))::geography)+1)+log(CASE WHEN v.voie_osm like 'Boulevard%' THEN 4 WHEN v.voie_osm LIKE 'Place%' THEN 4 WHEN v.voie_osm LIKE 'Espl%' THEN 4 WHEN v.voie_osm LIKE 'Av%' THEN 3 WHEN v.voie_osm LIKE 'Rue %' THEN 2 ELSE 1 END))::numeric,4) ||' ,\"housenumbers\":' || concat('{',string_agg(concat('\"',replace(replace(replace(osm.numero,' ',''),'\"',''),'\\',''),'\": {\"lat\": ',round(st_y(osm.geometrie)::numeric,6),',\"lon\": ',round(st_x(osm.geometrie)::numeric,6),'}'), ','),'}}') AS sjson
FROM cumul_voies v
JOIN communes c ON (insee=insee_com)
JOIN code_cadastre cad ON (cad.insee_com=v.insee_com)
LEFT JOIN cumul_adresses osm ON (osm.fantoir=v.fantoir)
JOIN
  (SELECT fantoir,
          replace(numero,' ','') AS num,
          max(SOURCE) AS src
   FROM cumul_adresses
   WHERE fantoir LIKE '$1%'
   GROUP BY 1,
            2) AS b ON (b.fantoir=osm.fantoir
                        AND osm.SOURCE=b.src
                        AND b.num=replace(osm.numero,' ',''))
LEFT JOIN (select dep, nom_dep, nom_reg from cog group by dep, nom_dep, nom_reg) as cog ON (cog.dep=left(v.insee_com,2) or cog.dep=left(v.insee_com,3))
LEFT JOIN geofla_plus g ON (g.insee=v.insee_com)
LEFT JOIN postal_code cp ON (cp.insee=v.insee_com AND ST_Contains(cp.wkb_geometry, osm.geometrie))
WHERE v.fantoir LIKE '$1%'
  AND osm.numero ~ '^[0-9]{1,4}( ?[A-Z]?.*)?'
  AND osm.numero !~'.[0-9 \\.\\-]{9,}'
GROUP BY v.fantoir,
         v.voie_osm,
         cad.code_postal, cp.postal_cod,
         v.geometrie,
         c.nom, cp.nom,
         cog.nom_dep,
         cog.nom_reg,
         g.statut,
         g.population
ORDER BY v.fantoir;
" >> tmp-$1-full.json


echo "`date +%H:%M:%S` Voie rapprochées sans adresses $1"
# export cumul_voie (position centre de voirie) > json
psql cadastre -t -A -c " \
SELECT '{\"id\": \"' || v.fantoir || CASE WHEN coalesce(cp.postal_cod, cad.code_postal)!=cad.code_postal THEN ('_' || cp.postal_cod) ELSE '' END || '\",\"type\": \"street\",\"name\": \"' || replace(replace(v.voie_osm,'\"',''),'’',chr(39)) || '\",\"postcode\": \"' || coalesce(cp.postal_cod, cad.code_postal) || CASE WHEN replace(lower(cp.nom),'-',' ') != replace(lower(c.nom),'-',' ') THEN '\",\"post_office\": \"' || cp.nom ELSE '' END || '\",\"lat\": \"' || round(st_y(v.geometrie)::numeric,6) || '\",\"lon\": \"' || round(st_x(v.geometrie)::numeric,6) || '\",\"city\": \"' || c.nom || '\",\"departement\": \"' || cog.nom_dep || '\", \"region\": \"' || cog.nom_reg || '\",\"importance\": '|| round(log((CASE WHEN (cad.code_postal LIKE '75%' OR g.statut LIKE 'Capital%') THEN 6 WHEN (cad.code_postal LIKE '690%' OR cad.code_postal LIKE '130%' OR g.statut = 'Préfecture de régi') THEN 5 WHEN g.statut='Préfecture' THEN 4 WHEN g.statut LIKE 'Sous-pr%' THEN 3 WHEN g.statut='Chef-lieu canton' THEN 2 ELSE 1 END)+log(g.population+1)/3)::numeric*log(1+log(count(a.*)+1)+log(CASE WHEN v.voie_osm like 'Boulevard%' THEN 4 WHEN v.voie_osm LIKE 'Place%' THEN 4 WHEN v.voie_osm LIKE 'Espl%' THEN 4 WHEN v.voie_osm LIKE 'Av%' THEN 3 WHEN v.voie_osm LIKE 'Rue %' THEN 2 ELSE 1 END))::numeric,4) ||' }' AS sjson
FROM cumul_voies v
JOIN communes c ON (insee=insee_com)
JOIN code_cadastre cad ON (cad.insee_com=v.insee_com)
LEFT JOIN (select dep, nom_dep, nom_reg from cog group by dep, nom_dep, nom_reg) as cog ON (cog.dep=left(v.insee_com,2) or cog.dep=left(v.insee_com,3))
LEFT JOIN geofla_plus g ON (g.insee=v.insee_com)
LEFT JOIN postal_code cp ON (cp.insee=v.insee_com AND ST_Contains(cp.wkb_geometry, v.geometrie))
LEFT JOIN cumul_adresses a ON (a.fantoir=v.fantoir)
WHERE v.fantoir LIKE '$1%'
  AND a.numero IS NULL
GROUP BY v.fantoir,
         v.voie_osm,
         cad.code_postal, cp.postal_cod,
         v.geometrie,
         c.nom, cp.nom,
         cog.nom_dep,
         cog.nom_reg,
         g.statut,
         g.population
ORDER BY v.fantoir;
" >> tmp-$1-full.json


echo "`date +%H:%M:%S` LD $1"
# export cumul_place (lieux-dits) > json
psql cadastre -t -A -c "
with u as (select fantoir as f, insee_com as insee from cumul_places where fantoir like '$1%' GROUP BY 1,2)
select '{\"id\": \"' || u.f || '\",\"type\": \"' || coalesce(o.ld_osm, 'place') || '\",\"name\": \"' || replace(replace(coalesce(o.libelle_osm, c.libelle_cadastre),'\"',''),'’',chr(39)) || '\",\"postcode\": \"' || coalesce(cp.postal_cod, ca.code_postal) || CASE WHEN replace(lower(cp.nom),'-',' ') != replace(lower(coalesce(cn.nom,initcap(ca.nom_com))),'-',' ') THEN '\",\"post_office\": \"' || cp.nom ELSE '' END || '\",\"lat\": \"' || case when o.geometrie is not null then round(st_y(o.geometrie)::numeric,6) else st_y(c.geometrie) end || '\",\"lon\": \"' || case when o.geometrie is not null then round(st_x(o.geometrie)::numeric,6) else st_x(c.geometrie) end || '\",\"city\": \"' || coalesce(cn.nom,initcap(ca.nom_com)) || '\",\"departement\": \"' || cog.nom_dep || '\", \"region\": \"' || cog.nom_reg || '\", \"importance\": '|| least(0.05,round(log((CASE WHEN g.statut LIKE 'Capital%' THEN 6 WHEN g.statut = 'Préfecture de régi' THEN 5 WHEN g.statut='Préfecture' THEN 4 WHEN g.statut LIKE 'Sous-pr%' THEN 3 WHEN g.statut='Chef-lieu canton' THEN 2 ELSE 1 END)+log(g.population+1)/3)*(0.25+0.5*(1-('0' || coalesce(f.ld_bati,'1'))::numeric)),4)) ||'}'
from u
	LEFT JOIN fantoir_voie f on (f.code_insee=u.insee AND u.f = concat(f.code_insee,f.id_voie,f.cle_rivoli))
	LEFT JOIN cumul_places c on (c.fantoir=u.f and c.source='CADASTRE')
	LEFT JOIN cumul_places o on (o.fantoir=u.f and o.source='OSM')
	LEFT JOIN code_cadastre ca ON (ca.insee_com=u.insee)
	LEFT JOIN communes cn ON (cn.insee=u.insee)
	LEFT JOIN geofla_plus g ON (g.insee=u.insee)
    LEFT JOIN postal_code cp ON (cp.insee=u.insee AND ST_Contains(cp.wkb_geometry, o.geometrie))
	JOIN (select dep, nom_dep, nom_reg from cog group by dep, nom_dep, nom_reg) as cog ON (cog.dep=left(u.insee,2) or cog.dep=left(u.insee,3))
where coalesce(o.libelle_osm, c.libelle_cadastre) != cn.nom ;
" >> tmp-$1-full.json


echo "`date +%H:%M:%S` FIN $1"

