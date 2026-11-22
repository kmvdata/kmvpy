{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Python: 当前文件",
      "type": "debugpy",
      "request": "launch",
      "program": "${file}",
      "console": "integratedTerminal",
      "cwd": "${workspaceFolder}/__PY_PROJECT_NAME__",
      "env": {
        "PYTHONPATH": "${workspaceFolder}/__PY_PROJECT_NAME__:${env:PYTHONPATH}"
      },
      "justMyCode": false,
      "python": "${command:python.interpreterPath}"
    },
    {
      "name": "Python: Uvicorn __PROJECT_NAME__",
      "type": "debugpy",
      "request": "launch",
      "module": "uvicorn",
      "args": [
        "app.run:create_app",
        "--factory",
        "--reload"
      ],
      "console": "integratedTerminal",
      "cwd": "${workspaceFolder}/__PY_PROJECT_NAME__",
      "env": {
        "PYTHONPATH": "${workspaceFolder}/__PY_PROJECT_NAME__:${env:PYTHONPATH}"
      },
      "justMyCode": false,
      "python": "${command:python.interpreterPath}"
    }
  ]
}
