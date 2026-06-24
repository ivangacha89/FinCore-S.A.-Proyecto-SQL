-- ---------------------------------------------
-- Consultas analisis
-- ---------------------------------------------

select * from auditoria_prestamos;
select * from resumen_mensual;

select * from clientes;
select * from pagos;
select * from prestamos;
select * from productos_credito;

select count(*) as cantidad_tabla_auditoria_prestamos from auditoria_prestamos;
select count(*) as cantidad_tabla_resumen_mensual from resumen_mensual;

select count(*) as cantidad_tabla_clientes from clientes;
select count(*) as cantidad_tabla_pagos from pagos;
select count(*) as cantidad_tabla_prestamos from prestamos;
select count(*) as cantidad_tabla_credito from productos_credito;

-- query para prueba de la funcion fn_clasificar_mora
select 
	id_prestamo,
    dias_mora,
	fn_clasificar_mora(dias_mora) as categoria_aging
from prestamos;

select * from vw_estado_cartera; -- consulta de la vista vw_estado_cartera

select * from vw_resumen_clientes; -- consulta de la vista vw_resumen_clientes

-- ---------------------------------------------
-- Análisis avanzado de cartera
-- ---------------------------------------------

-- Aging de cartera: agrupa todos los préstamos activos y vencidos por su tramo de mora, mostrando cantidad, saldo en riesgo y porcentaje del total.

-- Opcion 1, muestra solo los tramos contenidos en la informacion: Al dia, Mora Grave, Mora Critica
select
	case -- casos evaluados para asignar un numero y poder hacer ordenamiento logico al mostrar la informacion
		when fn_clasificar_mora(dias_mora) = "Al día" collate utf8mb4_unicode_ci then 1
        when fn_clasificar_mora(dias_mora) = "Mora Temprana (1-30d)" collate utf8mb4_unicode_ci then 2 
        when fn_clasificar_mora(dias_mora) = "Mora Media (31-60d)" collate utf8mb4_unicode_ci then 3
        when fn_clasificar_mora(dias_mora) = "Mora Grave (61-90d)" collate utf8mb4_unicode_ci then 4
        else 5
	end as ordenamiento,
    fn_clasificar_mora(dias_mora) as tramo_de_mora,
    count(*) as "# prestamos",
    sum(saldo_pendiente) as saldo_en_riesgo,
    round(sum(saldo_pendiente) /
    (select sum(saldo_pendiente)
    from prestamos
    where estado in ("Activo", "Vencido")) * 100, 2) as "% del total" -- se utiliza una subquery para calcular el % del total y se redondea la cifra a dos decimales
from prestamos
where estado in ("Activo", "Vencido")
group by ordenamiento, fn_clasificar_mora(dias_mora)
order by ordenamiento asc;

-- Opcion 2, muestra todos los tramos de la cartera

-- Paso 1: se crea una tabla temporal para ejecutar la query con todos los tramos posibles
WITH tramos AS (
    SELECT 1 AS orden, 'Al día' AS tramo
    UNION ALL SELECT 2, 'Mora Temprana (1-30d)'
    UNION ALL SELECT 3, 'Mora Media (31-60d)'
    UNION ALL SELECT 4, 'Mora Grave (61-90d)'
    UNION ALL SELECT 5, 'Mora Crítica (+90d)'
)

-- Paso 2: LEFT JOIN con los préstamos reales y la tabla temporal, se utiliza coalesce sobre los valores null para visualizar la informacion de forma correcta
SELECT 
    t.orden,
    t.tramo AS tramo_de_mora,
    COALESCE(COUNT(p.id_prestamo), 0)    AS "# prestamos",
    COALESCE(SUM(p.saldo_pendiente), 0)  AS saldo_en_riesgo,
    COALESCE(ROUND(SUM(saldo_pendiente) /
		(SELECT SUM(saldo_pendiente)
		FROM prestamos
		WHERE estado IN ("Activo", "Vencido")) * 100, 2), 0) AS "% del total"
FROM tramos t
LEFT JOIN prestamos p
    ON fn_clasificar_mora(p.dias_mora) COLLATE utf8mb4_unicode_ci = t.tramo 
    AND p.estado IN ('Activo', 'Vencido') -- busca los prestamos reales que corresponden al tramo para hacer la comparacion
GROUP BY t.orden, t.tramo
ORDER BY t.orden;

-- Top 5 de exposición crediticia: identifica los 5 clientes con mayor saldo pendiente total y compara cada uno contra el promedio de la cartera.

-- Para resolver esta pregunta se reutiliza la vista vw_resumen_clientes que contiene la informacion relevante
with promedio as (
	select round(avg(saldo_pendiente_consolidado), 2) as valor
    from vw_resumen_clientes
    ) -- se crea una la CTE (Common Table Expression) promedio, para calcular el promedio una sola vez y reutilizarlo
select 
	cliente,
    saldo_pendiente_consolidado as saldo_total,
    p.valor as promedio_cartera,
    saldo_pendiente_consolidado - p.valor as diferencia
from vw_resumen_clientes, promedio p -- al from se agrega la tabla temporal promedio
order by saldo_pendiente_consolidado desc
limit 5;

-- Historial de pagos completo: cruza las tablas pagos, prestamos, clientes y productos_credito para mostrar el detalle de los últimos 20 pagos registrados.

/*
Para resolver esta pregunta se reutiliza la vista vw_estado_cartera que contiene la informacion relevante
y se hace el cruce con la tabla pagos, ya que tienen la columna en comun id_prestamo
*/
select
	pg.id_prestamo,
	pr.cliente,
    pr.producto,
    pg.monto_pagado,
    pg.fecha_pago,
    pg.canal
from 
	pagos pg
join 
	vw_estado_cartera pr on pg.id_prestamo = pr.id_prestamo
order by
	pg.fecha_pago desc
limit 20;

/*
Reporte ejecutivo: usando la vista vw_estado_cartera, agrupa la cartera por segmento y categoría de riesgo,
mostrando tasa promedio, créditos vencidos y porcentaje de cartera en riesgo.
*/
select 
	e.segmento,
    e.categoria_riesgo,
    -- se utiliza una subconsulta para obtener el promedio, cuando el segmento y la categoria_riesgo concuerden
    round((select avg(i.tasa_aplicada) from vw_estado_cartera i where i.segmento = e.segmento and i.categoria_riesgo = e.categoria_riesgo), 2) as tasa_promedio,
    -- se utiliza un case en la funcion de agregacion para sumar unicamente los casos cuando el estado sea Vencido
    sum(case when estado = "Vencido" then 1 else 0 end) as creditos_vencidos,
    -- el numerador de la division se obtiene unicamente sumando los casos cuando dias_mora supere el valor de 0
    round(
		sum(
			case
				when e.dias_mora > 0
                then e.saldo_pendiente
                else 0
			end
        ) /
        -- el denominador del % es el saldo total de toda la cartera
        (
			select sum(i2.saldo_pendiente)
			from vw_estado_cartera i2
        ) * 100,
    2) as pct_cartera_en_riesgo
from 
	vw_estado_cartera e
group by
	segmento, categoria_riesgo;