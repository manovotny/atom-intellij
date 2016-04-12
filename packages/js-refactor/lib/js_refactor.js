'use babel'

export const activate = () => {
	if (atom.packages.isPackageLoaded('refactor')) return
	atom.notifications.addWarning(
		'js-refactor package requires refactor package',
		{
			detail: 'You can install and activate refactor package using the preference pane.'
		}
	)
}

export Ripper from './ripper'
