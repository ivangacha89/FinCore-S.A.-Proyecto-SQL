-- Crea los índices que consideres necesarios sobre las columnas con mayor uso en filtros y JOIN.

create index idx_pagos_prestamo on pagos(id_prestamo);

create index idx_pagos_fecha on pagos(fecha_pago);

-- prestamos: columnas de filtro mas usadas
create index idx_prestamos_estado on prestamos(estado);

create index idx_prestamos_dias_mora on prestamos(dias_mora);

-- prestamos: columnas de join
create index idx_prestamos_cliente on prestamos(id_cliente);

create index idx_prestamos_producto on prestamos(id_producto);

-- clientes: filtros del reporte ejecutivo
-- indice compuesto que cubre dos columnas juntas, ya que siempre aparecen combinadas en el group by del reporte ejecutivo
create index idx_clientes_segmento_riesgo on clientes(segmento, categoria_riesgo);