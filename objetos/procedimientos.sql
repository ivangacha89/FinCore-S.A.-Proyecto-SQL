-- ---------------------------------------------
-- Procedimientos almacenados
-- ---------------------------------------------
/*
Se crea el procedimiento sp_registrar_pago: que recibe los siguientes parametros: ID del préstamo, monto, tipo de pago y canal.
el procedimiento valida que el préstamo exista y esté activo (o vencido),
si se cumplen estas condiciones se inicia una transacción con manejo de errores,
dondea se ctualiza el saldo pendiente, se registra el pago y ademas si el saldo llega a cero, se debe cambiar el estado a Cancelado.
*/

delimiter //
create procedure sp_registrar_pago(in p_id_prestamo int, in p_monto_pagado decimal(10, 2), in p_tipo_pago varchar(20), in p_canal varchar(30), out p_resultado varchar(100))
begin
	-- se declaran dos variables locales, que tomaran los valores del estado del credito y el saldo pendiente de la tabla prestamos
	declare v_estado varchar(20);
    declare v_saldo decimal(10, 2);
    declare v_nuevo_saldo decimal(10, 2);
	
    -- handler de errores, si cualquier error ocurre durante la ejecucion, el procedimiento se detiene inmediatamente
	declare exit handler for sqlexception
    begin
		rollback;
        set p_resultado = "ERROR: Fallo inesperado en la transacción";
    end;
    
    -- se insertan valores a las variables declaradas dependiendo del id ingresado, si el id no existe quedan en null
    select estado, saldo_pendiente
    into v_estado, v_saldo
    from prestamos
    where id_prestamo = p_id_prestamo;
    
	-- condicion que valida que el préstamo exista, evaluando que el valor de v_estado sea diferente de null
	if v_estado is not null then
		-- condicion que valida que el préstamo esté activo (o vencido)
		if v_estado in ("Activo", "Vencido") then
			-- si se cumplen las dos condiciones empieza la transaccion
            
			set v_nuevo_saldo = greatest(v_saldo - p_monto_pagado, 0);
            
			start transaction;
				-- se actualiza la tabla prestamos y la columna saldo_pendiente
				update prestamos
                set saldo_pendiente = v_nuevo_saldo 
                where id_prestamo = p_id_prestamo;
                
                -- se insertan valores en la tabla pagos
                insert into pagos (id_prestamo, fecha_pago, monto_pagado, tipo_pago, canal)
                values (p_id_prestamo, curdate(), p_monto_pagado, p_tipo_pago, p_canal);
                
                -- -- condicion que evalua que el saldo pendiente sea = 0 para cambiar el estado del credito a Cancelado
                if v_nuevo_saldo = 0 then
					update prestamos
                    set estado = "Cancelado"
                    where id_prestamo = p_id_prestamo;
                end if;
                set p_resultado = concat("Ok: Pago registrado. Nuevo saldo: ", v_nuevo_saldo);
			commit;
        else
			rollback;
			-- cumple el indicador: rechaza Cancelado y Refinanciado
			set p_resultado = concat("ERROR: Prestamo en estado ", v_estado, " no admite pagos");
        end if;
    else
		rollback;
		set p_resultado = "ERROR: Prestamo no encontrado";
    end if;
	
end //

delimiter ;

-- select * from prestamos where id_prestamo = 1;
-- delete from pagos where id_pago = 49;
-- update prestamos set saldo_pendiente = 28000.00, estado = "Activo" where id_prestamo = 1;

-- escenario de prueba 1
select id_prestamo, saldo_pendiente, estado from prestamos where id_prestamo = 1; -- validacion del prestamo antes de ejecutar el procediminto
-- prestamo activo, en el cual se paga la totalidad del saldo pendiente y se cambia el estado a cancelado
call sp_registrar_pago(1, 28000.00, "Cuota", "App", @resultado);
select @resultado; -- variable que indica el resultado de la transaccion (Efectivo)
-- validacion del prestamo despues de ejecutar el procediminto, cambios en saldo pendiente y estado
select id_prestamo, saldo_pendiente, estado from prestamos where id_prestamo = 1; 
select * from pagos where id_prestamo = 1 order by id_pago desc; -- validacion que el pago realizado se registra en la tabla

-- escenario de prueba 2, 
select id_prestamo, saldo_pendiente, estado from prestamos where id_prestamo = 20; -- validacion del prestamo antes de ejecutar el procediminto
-- prestamo Refinanciado, no tendria que restar el saldo, ya que no cumple la condicion del estado
call sp_registrar_pago(20, 1990.00, "Cuota", "App", @resultado);
select @resultado; -- variable que indica el resultado de la transaccion (No efectivo)
-- validacion del prestamo despues de ejecutar el procediminto, no debe tener cambios en saldo pendiente y estado
select id_prestamo, saldo_pendiente, estado from prestamos where id_prestamo = 20; 
select * from pagos where id_prestamo = 20 order by id_pago desc; -- validacion que no se registra el pago en la tabla pagos

/*
Se crea el procedimiento sp_generar_resumen_mensual: que recibe los siguientes parametros: año y mes,
calcula los indicadores del período ingresado (préstamos otorgados, monto total, pagos recibidos, tasa de morosidad, prestamos vencidos)
y los inserta o actualiza en la tabla resumen_mensual
*/
delimiter //

create procedure sp_generar_resumen_mensual(in p_anio int, in p_mes int)
begin
	-- se declaran variables locales  para calcular los cinco indicadores que se insertaran a la tabla resumen_mensual
	declare prestamos_otorgados int;
    declare monto_total decimal(10, 2);
    declare pagos_recibidos decimal(10, 2);
    declare v_prestamos_vencidos int;
    declare v_tasa_morosidad decimal(5, 2);
    
    -- se carga el valor a las variables prestamos_otorgados, monto_total teniendo en cuenta el filtro de año y mes de la tabla prestamos
    select
		count(*),
        sum(monto_otorgado)
	into
		prestamos_otorgados,
        monto_total
	from
		prestamos
    where
		year(fecha_otorgamiento) = p_anio and
        month(fecha_otorgamiento) = p_mes;
	
    -- se carga el valor a la variable pagos_recibidos teniendo en cuenta el filtro de año y mes de la tabla pagos
	select
		sum(monto_pagado)
	into
		pagos_recibidos
	from
		pagos
    where
		year(fecha_pago) = p_anio and
        month(fecha_pago) = p_mes;
	
    -- se carga el valor a la variable prestamos_vencidos teniendo en cuenta el filtro de año, mes y estado del prestado vencido de la tabla prestamos
	select
		count(*)
	into
		v_prestamos_vencidos
	from
		prestamos
    where
		year(fecha_otorgamiento) = p_anio and
        month(fecha_otorgamiento) = p_mes and
        estado = "Vencido";
        
	-- se setea la variable tasa_morocidad con los valores obtenidos y se incluye manejo de division por cero con nullif()
    set v_tasa_morosidad = v_prestamos_vencidos / nullif(prestamos_otorgados, 0) * 100;
    
    -- se insertan los valores obtenidos en la tabla resumen_mensual
    insert into resumen_mensual (
		anio,
        mes,
        total_prestamos,
        monto_total_otorgado,
        total_pagos_recibidos,
        prestamos_vencidos,
        tasa_morosidad
        )
	values (
		p_anio,
        p_mes,
        prestamos_otorgados,
        monto_total,
        pagos_recibidos,
        v_prestamos_vencidos,
        v_tasa_morosidad
    ) as nuevo
    -- teniendo en cuenta que la tabla tiene unique key (anio, mes) no permitira insertar el mismo valor, solo se actualizan los demas valores
    on duplicate key update
		total_prestamos = nuevo.total_prestamos,
        monto_total_otorgado = nuevo.monto_total_otorgado,
        total_pagos_recibidos = nuevo.total_pagos_recibidos,
        prestamos_vencidos = nuevo.prestamos_vencidos,
        tasa_morosidad = nuevo.tasa_morosidad,
        fecha_generacion = current_timestamp;
end //

delimiter ;

-- escenarios de prueba
call sp_generar_resumen_mensual(2023, 1);
call sp_generar_resumen_mensual(2023, 3);
call sp_generar_resumen_mensual(2022, 6);
select * from resumen_mensual;


/*
Se crea el procedimiento sp_refinanciar_prestamo: que recibe como parametros: ID del préstamo a refinanciar, el nuevo plazo en meses y la nueva tasa.
Debe marcar el préstamo original como Refinanciado y crear uno nuevo con el saldo pendiente como monto,
dentro de una transacción que garantice que ambas operaciones se realicen juntas o ninguna.
*/
delimiter //
create procedure sp_refinanciar_prestamo(in p_id_prestamo int, in p_plazo_meses int, in p_tasa_aplicada decimal(5, 2))
begin
	-- declaracion de variables locales que toman valores de la tabla prestamos 
	declare v_id_cliente int;
    declare v_id_producto int;
    declare saldo_actual decimal(10, 2);
    declare v_estado varchar(20);
    
    -- declaracion de variables locales que permiten hacer calculos e insertar los nuevos valores al nuevo registro de prestamos
    declare v_monto_otorgado decimal(10, 2);
    declare nueva_tasa decimal(5, 2);
    declare nuevo_plazo int;
    declare v_fecha_otorgamiento date;
    declare v_fecha_vencimiento date;
    declare v_cuota_mensual decimal(10, 2);
    declare v_tasa_mensual decimal(10, 6);
	
    -- handler de errores, si cualquier error ocurre durante la ejecucion, el procedimiento se detiene inmediatamente
	declare exit handler for sqlexception
    begin
		rollback;
    end;
    
    select
		id_cliente,
		id_producto,
		saldo_pendiente,
        estado
    into
		v_id_cliente,
		v_id_producto,
		saldo_actual,
        v_estado
    from
		prestamos
    where
		id_prestamo = p_id_prestamo;
	
    -- validacion para determinar que el credito si existe
    if v_id_cliente is null then
		signal sqlstate "45000"
        set message_text = "Prestamo en encontrado";
	end if;
    
    -- validacion para determinar que el credito esta en un estado correcto para refinanciar
    if v_estado not in ("Activo", "Vencido") then
		signal sqlstate "45000"
        set message_text = "El prestamo no puede refinanciarse";
	end if;
    
    -- seteo de variables
    set v_monto_otorgado = saldo_actual; -- el nuevo monto otorgado sera el saldo actual del prestamo
    set v_fecha_otorgamiento = curdate(); -- sera la fecha actual del servidor
    set nueva_tasa = p_tasa_aplicada; -- el valor que recibe como parametro
    set nuevo_plazo = p_plazo_meses; -- el valor que recibe como parametro
    -- se suma a v_fecha_vencimiento la cantidad de meses del nuevo plazo
    set v_fecha_vencimiento = date_add(v_fecha_otorgamiento, interval nuevo_plazo month);
    -- cuota de amortizacion francesa
    set v_tasa_mensual = nueva_tasa / 100 / 12;
    set v_cuota_mensual = v_monto_otorgado * v_tasa_mensual / (1 - pow(1 + v_tasa_mensual, -nuevo_plazo));
    
    start transaction;
		
        -- actualizacion en la tabla prestamos que marca el préstamo original como Refinanciado
        update prestamos
        set estado = "Refinanciado"
        where id_prestamo = p_id_prestamo;
        
        -- creacion de un nuevo registro en la tabla prestramos, con el saldo_pendiente como monto_otorgado
        insert into prestamos (
			id_cliente,
			id_producto,
            monto_otorgado,
            tasa_aplicada,
            plazo_meses,
			fecha_otorgamiento,
            fecha_vencimiento,
			cuota_mensual,
			saldo_pendiente,
			estado,
			dias_mora
		)
        values (
			v_id_cliente,
			v_id_producto,
            v_monto_otorgado,
            nueva_tasa,
            nuevo_plazo,
			v_fecha_otorgamiento,
            v_fecha_vencimiento,
			v_cuota_mensual,
			saldo_actual,
			"Activo",
			0
		);
	
    commit;
	
end //

delimiter ;

-- escenario de prueba

-- antes del refinanciamiento
select id_prestamo, id_cliente, monto_otorgado, estado, fecha_otorgamiento 
from prestamos 
where id_cliente = 1 
order by id_prestamo;

-- Tomar un préstamo activo existente (id 1) y refinanciarlo
call sp_refinanciar_prestamo(1, 48, 20.00);

-- despues del refinanciamiento
select id_prestamo, id_cliente, monto_otorgado, estado, fecha_otorgamiento 
from prestamos 
where id_cliente = 1 
order by id_prestamo;