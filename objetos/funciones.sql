-- ---------------------------------------------
-- Funciones
-- ---------------------------------------------

/*
Funcion fn_clasificar_mora que toma como argumento los dias en mora del prestamo
retorna un varchar, segun la clasificacion de los dias en mora, de acuerdo con las
politicas internas, las cuales se dividen en cinco categorias dependiendo la
cantidad de dias en mora
*/
DELIMITER //

create function fn_clasificar_mora(p_dias_mora int) -- parametro de los dias en mora 
returns varchar(50)
deterministic
begin
	return case -- cinco casos evaluados dependiendo de la cantidad de dias en mora
		when p_dias_mora < 1 then "Al día"
        when p_dias_mora >= 1 and p_dias_mora <= 30 then "Mora Temprana (1-30d)"
        when p_dias_mora > 30 and p_dias_mora <= 60 then "Mora Media (31-60d)"
        when p_dias_mora > 60 and p_dias_mora <= 90 then "Mora Grave (61-90d)"
        else "Mora Crítica (+90d)"
	end;
end //

DELIMITER ;