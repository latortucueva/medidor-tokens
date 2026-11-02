# medidor-tokens

Barra fija arriba del prompt de Claude Code que muestra, después de cada respuesta, cuánto del contexto de la conversación está ocupado (barra, porcentaje y tokens) y, si el plan los informa, el uso de los límites de 5 horas y semanal, con la hora en que se renueva el de 5 horas. Se pone en rojo pasado el 80% y avisa con una notificación pasado el 90%.

## Instalación

En el prompt de una sesión de Claude Code:

```
/plugin install medidor-tokens --marketplace latortucueva/medidor-tokens
```

Desde una terminal:

```
claude plugin install medidor-tokens --marketplace latortucueva/medidor-tokens
```

Respondé `y` para agregar el marketplace y elegí el alcance (usuario, para todas tus sesiones).

## Widget flotante (Windows)

El plugin guarda el uso en `%USERPROFILE%\.claude\medidor-tokens.json` después de cada respuesta. La carpeta `widget/` trae una ventanita flotante, siempre encima de las demás apps, que lee ese archivo: hacé doble clic en `abrir-medidor.cmd`. Se arrastra con el mouse y se cierra con la ✕.
