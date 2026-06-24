-- ---------------------------------------------
-- Vistas
-- ---------------------------------------------

/*
Creacion de una vista llamada vw_estado_cartera, la cual permite consultar datos de los prestamos
sin necesidad de consultar otras tablas, se entrega una vista con la informacion mas relevante
por medio de un join de las tablas de: clientes, prestamos y productos_credito, se agregan dos columnas:
porcentaje_saldo_restante: calcula el porcentaje que se debe del total prestado
clasificacion_mora: se utiliza la funcion creada para categorizar el valor de los dias en mora
*/
create view vw_estado_cartera as
	select
		pr.id_prestamo,
		c.nombre as cliente,
		c.documento,
		c.email,
		c.telefono,
		c.ciudad,
		c.segmento,
		c.categoria_riesgo,
		pc.nombre as producto,
		pc.tipo,
		pr.monto_otorgado,
        pr.tasa_aplicada,
		pr.saldo_pendiente,
		pr.estado,
		pr.fecha_vencimiento,
		pr.dias_mora,
		round((saldo_pendiente/ (monto_otorgado) * 100), 1) as porcentaje_saldo_restante, -- columna que retorna el porcentaje del saldo restante
		fn_clasificar_mora(pr.dias_mora) as clasificacion_mora -- columna que retorna la clasificacion de los dias en mora usando la funcion fn_clasificar_mora
	from
		prestamos as pr
	join
		clientes as c on pr.id_cliente = c.id_cliente
	join
		productos_credito as pc on pr.id_producto = pc.id_producto;
        
/*
Creacion de una vista llamada vw_resumen_clientes, la cual permite ver un resumen
de la cantidad de prestamos adquiridos por un cliente, el monto total sumado de los
prestamos, el saldo pendiente consolidado de todos los prestamos, la mora maxima
alcanzada en alguno de sus prestamos y si tiene mora activa, dependiente si alguno de
sus creditos esta en estado activo o vencido
*/
create view vw_resumen_clientes as
	select
		c.id_cliente,
		c.nombre as cliente,
        c.segmento,
        c.categoria_riesgo,
		count(pr.id_cliente) as total_prestamos, -- conteo de los prestamos registrados
		sum(pr.monto_otorgado) as monto_total_otorgado, -- suma de todos los prestamos solicitados
		sum(pr.saldo_pendiente) as saldo_pendiente_consolidado, -- suma de montos pendientes de todos los prestamos solicitados
		max(pr.dias_mora) as dias_mora_maximos, -- valor maximo de dias en mora registrado
        if(count(pr.id_cliente) = 0, null, fn_clasificar_mora(max(pr.dias_mora))) as peor_clasificacion, -- clasifica el peor estado de mora del cliente
        -- case que evalua si esta en mora activa: (Si / No), dependiendo si el estado del credito esta en condicion de: (Activo / Vencido)
		max(case when pr.dias_mora > 0 and pr.estado in ("Activo", "Vencido") then "Si" else "No" end) as mora_activa
	from clientes as c
	left join prestamos pr on c.id_cliente = pr.id_cliente
	group by c.id_cliente, c.nombre;