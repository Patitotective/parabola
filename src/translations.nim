import ni18n

type
  Locale* = enum
    English = "English", Spanish = "Español"

i18nInit Locale, true:
  pluto:
    English = "Pluto"
    Spanish = "Plutón"
  moon:
    English = "Moon"
    Spanish = "Luna"
  mercAndMars:
    English = "Mercury & Mars"
    Spanish = "Mercurio & Marte"
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
    Spanish = "Rango máximo"
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
    Spanish = "Da doble click sobre una trajectoria\npara eliminarla"
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
    Spanish = "Mostrar la flecha combinada de velocidad"
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
    English = "Made by Patitotective. Source code in "
    Spanish = "Hecho por Patitotective. Código fuente en "

  #ihaveCat:
  #  English = "I've many cats."
  #  Chinese = "我有很多小猫。"
  #  Myanmar = "ငါ့ဆီမှာ ကြောင် အများကြီးရှိတယ်။"
  #  # translation definition can have sub-translation definition
  #  withCount:
  #    # translations can be lambda / closure
  #    English = proc(count: int): string =
  #      case count
  #      of 0: "I don't have a cat."
  #      of 1: "I have one cat."
  #      else: "I have " & $count & " cats."
