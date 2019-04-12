package com.cowbell.cordova.geofence;

import android.util.Log;

import java.util.LinkedList;
import java.util.Queue;
import java.util.concurrent.Semaphore;

public class GoogleServiceCommandExecutor implements IGoogleServiceCommandListener {
    private Queue<AbstractGoogleServiceCommand> commandsToExecute;
    private boolean isExecuting = false;
    private Semaphore semaphore = new Semaphore(1);

    public GoogleServiceCommandExecutor() {
        commandsToExecute = new LinkedList<AbstractGoogleServiceCommand>();
    }

    public void QueueToExecute(AbstractGoogleServiceCommand command) {
        try {
            semaphore.acquire();
            commandsToExecute.add(command);
        } catch (Exception e) {
            Log.e("GoogleServiceCommandExecutor", e.getMessage());
        } finally {
            semaphore.release();
        }
        if (!isExecuting) ExecuteNext();
    }

    private void ExecuteNext() {
        if (commandsToExecute.isEmpty()) return;
        isExecuting = true;
        AbstractGoogleServiceCommand command = commandsToExecute.poll();
        command.addListener(this);
        command.Execute();
    }

    @Override
    public void onCommandExecuted(Object error) {
        isExecuting = false;
        ExecuteNext();
    }
}
