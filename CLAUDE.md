# Playdate Flappy Game Development Guidelines

## Build Commands
- Compile game: `pdc source flappy.pdx`
- Run on simulator: `open flappy.pdx`
- Run on device: Connect Playdate and run `playdate install flappy.pdx`

## Code Style Guidelines
- **Naming Conventions**: 
  - Classes: UpperCamelCase (`TransformComponent`)
  - Functions/Variables: lowerCamelCase or snake_case
  - Constants: UPPERCASE_WITH_UNDERSCORES

- **Code Structure**:
  - Component-based architecture with Actors (Entities) and Systems
  - Use EventSystem for decoupled communication

- **Import Style**:
  - Use `import "CoreLibs/module"` at top of files
  - Group imports by category

- **Formatting**:
  - Indent with 4 spaces
  - Use local constants for core libraries: `local gfx <const> = playdate.graphics`

- **Error Handling**:
  - Validate parameters in component init functions
  - Use conditional logic for game states rather than try/catch