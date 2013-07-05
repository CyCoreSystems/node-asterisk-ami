path = require 'path'
module.exports = (grunt)->
  grunt.initConfig {
    pkg: grunt.file.readJSON 'package.json'
    nodeunit:
      all: ['test/**/*.coffee']
    coffeelint:
      options:
        no_trailing_whitespace:
          level: 'error'
        indentation:
          level: 'error'
        max_line_length:
          level: 'ignore'
      app: 'src/**/*.coffee'
    coffee:
      main:
        options:
          bare: true
        expand: true
        cwd: 'src/'
        src: ['**/*.coffee']
        dest: 'lib/'
        rename: (dest,src)->
          return path.join(dest,src.replace(/(\.[^\/.]*)?$/,'.js'))
  }

  grunt.loadNpmTasks 'grunt-coffeelint'
  grunt.loadNpmTasks 'grunt-contrib-coffee'
  grunt.loadNpmTasks 'grunt-contrib-nodeunit'

  grunt.registerTask 'default',[ 'coffeelint', 'coffee' ]
  grunt.registerTask 'test',[ 'coffeelint', 'coffee', 'nodeunit' ]

