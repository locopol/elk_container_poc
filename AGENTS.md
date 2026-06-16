## Project
Piloto de implementación Elasticsearch en contenedores docker

## Project description
El proyecto es necesario para validar e implementar de manera proactiva los elementos necesarios para poner en marcha un cluster de elasticsearch en su ultima versión disponible, habilitar todas sus caracteristicas, realizar pruebas funcionales y poner en marcha para su uso inmediato.
Para llevar a cabo el piloto, se utilizará docker, el resultado del piloto debe poner en marcha la solución completa de elastic (cluster, consola de administración, seguridad con certificados autogenerados), realizar pruebas funcionales del producto y generar el respectivo compose para utilizarlo en otras plataformas.

## App documentation
Docker: https://docs.docker.com/compose/
Elasticsearch: https://www.elastic.co/guide/en/elasticsearch/reference/8.19/index.html

## Environment
Local basado en windows, asume que el entorno local ya dispone de los binarios docker para desarrollar el piloto

# Tools
  - read_file
  - search_file_contents
  - find_files
  - write_file
  - string_replace
  - execute_bash

## Tasks

1. **Analiza la documentacion elasticsearch**: Busca en la documentación el mecanismo para instalar elasticsearch en docker y las opciones de seguridad requeridas para la comunicación entre contenedores.
2. **Diseña el docker compose para un cluster**: Diseña un compose que incluya lo necesario para que se configure automaticamente la seguridad de elasticsearch y la de sus puertos de comunicación, esta configuración debe quedar documentada para identificar donde hacer modificaciones en caso de requerirse a futuro.
3. **Valida el estado del cluster en docker**: Prueba el compose y valida que el estado de los contenedores del cluster elasticSearch funcionen correctamente, genera pruebas unitarias de ser necesario.
4. **Implementa credenciales custom**: El cluster debe permitir establecer la credencial administrador (o elastic) a través de personalización de parametros, valida la opción de incluirlo en el compose.
5. **Activa el monitoreo del cluster**: Activa la caracteristica de monitorear el estado del cluster de elasticSearch con sus herramientas internas.
6. **Almacena los elementos del piloto**: Todos los elementos validados y requeridos por el compose deben almacenarse en carpetas separadas del proyecto base, los scripts que se encargan de levantar el piloto de forma autonoma debe quedar en la raiz del proyecto.
7. **Genera un reporte de resultado**: Informa detalladamente el proyecto, sus elementos, requisitos y su automatización, genera un README con el informe respectivo en formato Markdown estandar

## Constraints

- Apply scripting often by necesary
- Don't use emojis
- Use `unittest.mock` for mocking — do not install external test dependencies unless the project already uses them
- Keep tests fast and deterministic; avoid sleeps or non-deterministic behavior
- Always run tests after writing and report the final pass/fail result
- If the project has an existing test suite, add to it rather than replacing
