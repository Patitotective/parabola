import ni18n

type
  Locale* = enum
    English = "English", Spanish = "Español"

i18nInit Locale, true:
  pluto:
    English = "Pluto"
    Spanish = "Plutón"
  moon:
    English = "The Moon"
    Spanish = "La Luna"
  mercAndMars:
    English = "Mercury & Mars"
    Spanish = "Mercurio Y Marte"
  uranus:
    English = "Uranus"
    Spanish = "Urano"
  venus:
    English = "Venus"
    Spanish = "Venus"
  saturn:
    English = "Saturn"
    Spanish = "Saturno"
  earth:
    English = "Earth"
    Spanish = "Tierra"
  neptune:
    English = "Neptune"
    Spanish = "Neptuno"
  jupiter:
    English = "Jupiter"
    Spanish = "Júpiter"

  vix:
    English = "Initial X vel"
    Spanish = "Vel inicial en X"
  viy:
    English = "Initial Y vel"
    Spanish = "Vel inicial en Y"
  maxHeight:
    English = "Max height"
    Spanish = "Altura máxima"
  disabledMaxHeight:
    English = "The canon cannot point downwards"
    Spanish = "El cañón no puede apuntar hacia abajo"
  timeOfFlight:
    English = "Time of flight"
    Spanish = "Tiempo de vuelo"
  maxRange:
    English = "Max range"
    Spanish = "Alcance máximo"
  height:
    English = "Height"
    Spanish = "Altura"
  angle:
    English = "Angle"
    Spanish = "Ángulo"
  speed:
    English = "Speed"
    Spanish = "Rapidez"
  vx:
    English = "X Vel"
    Spanish = "Vel en X"
  vy:
    English = "Y Vel"
    Spanish = "Vel en Y"
  gravity:
    English = "Gravity"
    Spanish = "Gravedad"
  x:
    English = "X Pos"
    Spanish = "Pos en X"
  y:
    English = "Y Pos"
    Spanish = "Pos en Y"
  t:
    English = "Time"
    Spanish = "Tiempo"
  followBullet:
    English = "Follow bullet"
    Spanish = "Seguir la bala"
  noPoint:
    English = "Select a trajectory point"
    Spanish = "Selecciona un punto de la trayectoria"
  settings:
    English = "Settings"
    Spanish = "Configuración"
  timeScale:
    English = "Time Scale"
    Spanish = "Escala del tiempo"
  lang:
    English = "Language"
    Spanish = "Idioma"
  trajecs:
    English = "Trajectories"
    Spanish = "Trayectorias"
  trajTooltip:
    English = "Double-click a trajectory to delete it"
    Spanish = "Da doble clic sobre una trajectoria\npara eliminarla"
  iniState:
    English = "Initial State"
    Spanish = "Estado Inicial"
  point:
    English = "Trajectory Point"
    Spanish = "Punto de la trayectoria"
  formulas:
    English = "Equations"
    Spanish = "Equaciones"
  showVxArrow:
    English = "Show X velocity arrow"
    Spanish = "Mostrar la flecha de velocidad en X"
  showVyArrow:
    English = "Show Y velocity arrow"
    Spanish = "Mostrar la flecha de velocidad en Y"
  showVArrow:
    English = "Show combined velocity arrow"
    Spanish = "Mostrar la flecha de velocidad combinada"
  bulletsLimit:
    English = "Bullets limit"
    Spanish = "Límite de balas"
  showFormulaResults:
    English = "Show equations' solutions"
    Spanish = "Mostrar los resultados de las equaciones"
  #hiddenFormula:
  #  English = "To show the results, check the settings"
  #  Spanish = "Para mostrar los resulados, \nabre la configuración"
  starsAnimation:
    English = "Animate background stars"
    Spanish = "Animar las estrellas de fondo"
  aboutMsg:
    English = "v$v Made by Patitotective. Source code in "
    Spanish = "v$v Hecho por Patitotective. Código fuente en "
  animationWarning:
    English = "Has a high impact in the performance"
    Spanish = "Tiene un alto impacto en el rendimiento"
  help:
    English = "Help"
    Spanish = "Ayuda"
  help1:
    English = "You can change the initial angle of the canon by dragging the canon or by pressing the right and left keys."
    Spanish = "Puedes cambiar el ángulo inicial del cañón arrastrando el cañon o presionando las flechas de derecha y izquierda."
  help2:
    English = "You can move the canon in the Y axis by dragging the base of the canon or the platform below the canon."
    Spanish = "Puedes mover el cañón en el eje Y arrastrando la base del cañón o la plataforma debajo del cañón."
  help3:
    English = "You can change the inital speed of the canon by moving the wheel on your mouse, by dragging with two fingers in your touchpad or by pressing the up and down keys."
    Spanish = "Puiedes cambiar la rapidez inicial del cañón moviendo la rueda del mouse, arrastrando con dos dedos en el touchpad o presionando las flechas de arriba y abajo."
  help4:
    English = "You can select any point in the trajectory by double-clicking and dragging the mouse, you can remove this point by double-clicking far from the trajectory."
    Spanish = "Puedes seleccionar cualquier punto en la trayectoria dando doble clic y arrastrando el mouse, puedes quitar este punto dando doble clic lejos de la trayectoria."
  help5:
    English = "You can pause the simulation by pressing the key P."
    Spanish = "Puedes pausar la simulación presionand la tecla P."
  help6:
    English = "You can fire a bullet by pressing the wheel on your mouse, pressing with three fingers in your touchpad or by pressing the spacebar."
    Spanish = "Puedes disparar una bala presionando la rueda del mouse, presionando con tres dedos en el touchpad o presionando la barra espaciadora."
  help7:
    English = "You can add a new trajectory by pressing the enter key and you can remove a trajectory by double-clicking its button."
    Spanish = "Puedes añadir una trayectoria nueva presionando la tecla enter y puedes quitar una trayectoria dando doble clic en su botón."
  help8:
    English = "You can grab any bullet or rectangle and move it around the screen."
    Spanish = "Puedes agarrar cualquier bala o rectángulo y moverlo alrededor de la pantalla."
  help9:
    English = "You can restart the simulation to the initial state by pressing the backspace key."
    Spanish = "Puedes reiniciar la simulación a su estado inicial presionando la tecla backspace o retroceso."
  help10:
    English = "Remember that all of the values are rounded to two decimal places."
    Spanish = "Recuerda que todos los valores están redondeados a dos decimales."

  helpFooter:
    English = "v$v Feel free to ask more questions or report bugs in "
    Spanish = "v$v Si tienes más preguntas o quieres reportar un problema visita "

  togglePauseTooltip:
    English = "Press P"
    Spanish = "Presiona la P"
  reloadTooltip:
    English = "Press backspace"
    Spanish = "Presiona retroceso"
  fireTooltip:
    English = "Press space or middle-click"
    Spanish = "Presiona espacio o\nda clic con la rueda"
  studentMode:
    English = "Student Mode"
    Spanish = "Modo Estudiante"
  teacherMode:
    English = "Teacher Mode"
    Spanish = "Modo Profesor"
  switchToStudentMode:
    English = "Switch to Student Mode"
    Spanish = "Cambiar a Modo Estudiante"
  switchToTeacherMode:
    English = "Switch to Teacher Mode"
    Spanish = "Cambiar a Modo Profesor"
  studentModeExplaination:
    English = "In Student Mode you will not be able to modify the settings. To switch back to Teacher Mode you will need the password you will enter now:"
    Spanish = "En el Modo Estudiante no vas a poder cambiar la configuración. Para volver al Modo Profesor necesitarás la contraseña que vas a ingresar ahora:"
  studentModeExplaination2:
    English = "This is useful if you don't want your students to see the solutions or the procedures for the equations if you lend them your computer."
    Spanish = "Esto es útil si no quieres que tus estudiantes vean las soluciones o los procedimientos de las equaciones si les prestas tu computador."
  collideWithBlocks:
    English = "Collide with blocks in flight"
    Spanish = "Colisionar con los bloques en vuelo"
  collideWithBlocksTooltip:
    English = "Enable bullet collision with the blocks\nwhile the bullets are flying"
    Spanish = "Permitir que las balas colisionen con los\nbloques cuando las balas estén en el aire"
  password:
    English = "Password"
    Spanish = "Contraseña"
  tooShortPassword:
    English = "The password is too short"
    Spanish = "La constraseña es muy corta"
  tooLongPassword:
    English = "The password is too long"
    Spanish = "La constraseña es muy larga"
  teacherModeExplaination:
    English = "To switch back to Teacher Mode you will have to enter the password that was set when switching to Student Mode."
    Spanish = "Para volver al Modo Profesor necesitas ingresar la contraseña que fue ingresada cuando se cambió al Modo Estudiante."
  showFormulaProc:
    English = "Show equations' procedures"
    Spanish = "Mostar los procedimientos de las equaciones"
  wrongPassword:
    English = "Wrong password"
    Spanish = "Contraseña incorrecta"
