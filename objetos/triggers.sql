-- ---------------------------------------------
-- Triggers
-- ---------------------------------------------

/*
Creacion de un trigger trg_auditoria_estado, el cual realiza hace registros automaticos
en la tabla auditoria_prestamos, se activa unicamente cuando se hace algun cambio en los
valores de las columnas estado o dias_mora de la tabla prestamos
*/
DELIMITER //

create trigger trg_auditoria_estado
after update on prestamos -- se activa despues de actualizar la tabla prestamos, unicamente si se modifican las columnas estado o dias_mora
for each row
begin
	-- se controla la insercion a la tabla auditoria_prestamos validando que el valor de estado sea diferente del antiguo
	if old.estado <> new.estado then
		insert into auditoria_prestamos (
			id_prestamo,
			campo_modificado, 
			valor_anterior, 
			valor_nuevo) -- insertara los valores en la tabla auditoria_prestamos
		values (
			old.id_prestamo,
			"estado", -- se ingresa el valor literal del campo modificado
			old.estado,
			new.estado);
	end if;
    -- se controla la insercion a la tabla auditoria_prestamos validando que el valor de dias_mora sea diferente del antiguo
    if old.dias_mora <> new.dias_mora then
		insert into auditoria_prestamos (
			id_prestamo,
			campo_modificado, 
			valor_anterior, 
			valor_nuevo) -- insertara los valores en la tabla auditoria_prestamos
		values (
			old.id_prestamo,
			"dias_mora", -- se ingresa el valor literal del campo modificado
			old.dias_mora,
			new.dias_mora);
	end if;
end;
//
DELIMITER ;

update prestamos -- modificacion de prueba en la tabla prestamos de los valores de estado y dias del id 1
set 
	estado = "Activo",
	dias_mora = 0
where id_prestamo = 1;

select * from auditoria_prestamos; -- query para verificar el funcionamiento del trigger